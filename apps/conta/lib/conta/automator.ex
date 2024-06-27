defmodule Conta.Automator do
  require Logger

  import Conta.Commanded.Application, only: [dispatch: 1]
  import Ecto.Query, only: [from: 2]

  alias Conta.Automator.Excel
  alias Conta.Automator.Lua
  alias Conta.Command.RemoveFilter
  alias Conta.Command.RemoveShortcut
  alias Conta.Command.SetAccountTransaction
  alias Conta.Command.SetFilter
  alias Conta.Command.SetInvoice
  alias Conta.Command.SetShortcut
  alias Conta.Projector.Automator.Filter
  alias Conta.Projector.Automator.Param
  alias Conta.Projector.Automator.Shortcut
  alias Conta.Repo

  @default_xlsx_name "export.xlsx"

  def list_shortcuts(automator \\ "default") do
    from(
      s in Shortcut,
      where: s.automator == ^automator,
      order_by: s.name
    )
    |> Repo.all()
  end

  def list_filters(automator \\ "default") do
    from(
      f in Filter,
      where: f.automator == ^automator,
      order_by: f.name
    )
    |> Repo.all()
  end

  def get_remove_shortcut(id) when is_binary(id),
    do: get_remove_shortcut(get_shortcut!(id))

  def get_remove_shortcut(%Shortcut{} = shortcut) do
    %RemoveShortcut{
      name: shortcut.name,
      automator: shortcut.automator
    }
  end

  def get_remove_filter(id) when is_binary(id),
    do: get_remove_filter(get_filter!(id))

  def get_remove_filter(%Filter{} = filter) do
    %RemoveFilter{
      name: filter.name,
      automator: filter.automator
    }
  end

  def get_set_shortcut(id) when is_binary(id),
    do: get_set_shortcut(get_shortcut!(id))

  def get_set_shortcut(%Shortcut{} = shortcut) do
    %SetShortcut{
      name: shortcut.name,
      automator: shortcut.automator,
      params: for %Param{} = shortcut_param <- shortcut.params do
        %SetShortcut.Param{
          name: shortcut_param.name,
          type: shortcut_param.type,
          options: shortcut_param.options
        }
      end,
      code: shortcut.code,
      language: shortcut.language
    }
  end

  def get_set_filter(id) when is_binary(id),
    do: get_set_filter(get_filter!(id))

  def get_set_filter(%Filter{} = filter) do
    %SetFilter{
      name: filter.name,
      automator: filter.automator,
      output: filter.output,
      params: for %Param{} = filter_param <- filter.params do
        %SetFilter.Param{
          name: filter_param.name,
          type: filter_param.type,
          options: filter_param.options
        }
      end,
      code: filter.code,
      language: filter.language
    }
  end

  def get_shortcut_by_name(automator \\ "default", name) do
    Repo.get_by(Shortcut, name: name, automator: automator)
  end

  def get_filter_by_name(automator \\ "default", name) do
    Repo.get_by(Filter, name: name, automator: automator)
  end

  def get_shortcut(automator \\ "default", id) do
    Repo.get_by(Shortcut, id: id, automator: automator)
  end

  def get_shortcut!(automator \\ "default", id) do
    Repo.get_by!(Shortcut, id: id, automator: automator)
  end

  def get_filter(automator \\ "default", id) do
    Repo.get_by(Filter, id: id, automator: automator)
  end

  def get_filter!(automator \\ "default", id) do
    Repo.get_by!(Filter, id: id, automator: automator)
  end

  def run_shortcut(automator \\ "default", name, params)

  def run_shortcut(automator, name, params) when is_binary(name) do
    if shortcut = get_shortcut_by_name(name) do
      run_shortcut(automator, shortcut, params)
    else
      {:error, :shortcut_not_found}
    end
  end

  def run_shortcut(_automator, %Shortcut{} = shortcut, params) do
    with :ok <- validate_params(shortcut.params, params),
         {:ok, %{"status" => "ok", "commands" => commands}} when is_list(commands) <- run(shortcut, params) do
      Logger.debug("received data from #{shortcut.language} shortcut script: #{inspect(commands)}")
      Enum.reduce_while(commands, :ok, &process_result/2)
    else
      {:error, _} = error -> error
      {:ok, return} -> {:error, {:invalid_code_return, return}}
      {:error, compile, _stacktrace} -> {:error, compile}
    end
  end

  defp run(%_{code: code, language: :lua}, params), do: Lua.run(code, params)

  def run_filter(automator \\ "default", name, params)

  def run_filter(automator, name, params) when is_binary(name) do
    if filter = get_filter_by_name(name) do
      run_filter(automator, filter, params)
    else
      {:error, :filter_not_found}
    end
  end

  def run_filter(_automator, %Filter{} = filter, params) do
    with :ok <- validate_params(filter.params, params),
         {:ok, result} <- run(filter, params) do
      Logger.debug("received data from #{filter.language} filter script: #{inspect(result)}")
      filter.output
      |> case do
        :json -> Jason.encode(result)
        :xlsx -> Excel.export(result, params["filename"] || @default_xlsx_name)
      end
      |> case do
        {:ok, {filename, content}} -> {:ok, {"application/vnd.ms-excel", to_string(filename), content}}
        {:ok, content} -> {:ok, {"application/json", nil, content}}
      end
    else
      {:error, _} = error -> error
      {:ok, return} -> {:error, {:invalid_code_return, return}}
      {:error, compile, _stacktrace} -> {:error, compile}
    end
  end

  defp process_result(%{"type" => "transaction", "data" => data}, :ok) do
    data
    |> SetAccountTransaction.changeset()
    |> Conta.EctoHelpers.get_result()
    |> case do
      %SetAccountTransaction{} = command ->
        Logger.debug("processing command: #{inspect(command)}")
        result = dispatch(command)
        if result == :ok do
          {:cont, :ok}
        else
          {:halt, result}
        end

      {:error, _} = error ->
        {:halt, error}
    end
  end

  defp process_result(%{"type" => "invoice", "data" => data}, :ok) do
    data
    |> SetInvoice.changeset()
    |> Conta.EctoHelpers.get_result()
    |> case do
      %SetInvoice{} = command ->
        Logger.debug("processing command: #{inspect(command)}")
        result = dispatch(command)
        if result == :ok do
          {:cont, :ok}
        else
          {:halt, result}
        end

      {:error, _} = error ->
        {:halt, error}
    end
  end

  defp validate_params([], _params), do: :ok

  defp validate_params([%Param{name: name}|_], params) when not is_map_key(params, name) do
    {:error, %{name => ["can't be blank"]}}
  end

  defp validate_params([%Param{type: :table} = param|automator_params], params) do
    param_value = params[param.name]
    if is_list(param_value) or is_map(param_value) do
      validate_params(automator_params, params)
    else
      {:error, %{param.name => ["is invalid"]}}
    end
  end

  defp validate_params([%Param{type: :account_name} = param|automator_params], params) do
    param_value = params[param.name]
    if is_list(param_value) and Enum.all?(param_value, &is_binary/1) do
      validate_params(automator_params, params)
    else
      {:error, %{param.name => ["is invalid"]}}
    end
  end

  defp validate_params([%Param{type: :string} = param|automator_params], params) do
    if is_binary(params[param.name]) do
      validate_params(automator_params, params)
    else
      {:error, %{param.name => ["is invalid"]}}
    end
  end

  defp validate_params([%Param{type: type} = param|automator_params], params) when type in [:money, :integer] do
    if is_integer(params[param.name]) or match?({_, ""}, Integer.parse(params[param.name] || "")) do
      validate_params(automator_params, params)
    else
      {:error, %{param.name => ["is invalid"]}}
    end
  end

  defp validate_params([%Param{type: :currency} = param|automator_params], params) do
    currencies =
      Money.Currency.all()
      |> Map.keys()
      |> Enum.map(&to_string/1)

    if params[param.name] in currencies do
      validate_params(automator_params, params)
    else
      {:error, %{param.name => ["is invalid"]}}
    end
  end

  defp validate_params([%Param{type: :options} = param|automator_params], params) do
    if params[param.name] in param.options do
      validate_params(automator_params, params)
    else
      {:error, %{param.name => ["is invalid"]}}
    end
  end

  defp validate_params([%Param{type: :date} = param|automator_params], params) do
    value = params[param.name]
    cond do
      is_struct(value, Date) ->
        validate_params(automator_params, params)

      is_binary(value) and Date.from_iso8601(value) ->
        validate_params(automator_params, params)

      :else ->
        {:error, %{param.name => ["is invalid"]}}
    end
  end

  defp to_list(struct) when is_struct(struct), do: Map.from_struct(struct) |> to_list()
  defp to_list(enum) when is_list(enum) or is_map(enum), do: Enum.map(enum, &to_list/1)
  defp to_list({i, j}) when is_integer(i) and is_integer(j), do: [i, j]
  defp to_list({key, value}), do: {to_list(key), to_list(value)}
  defp to_list(atom) when is_atom(atom), do: to_string(atom)
  defp to_list(otherwise), do: otherwise

  def cast(%Shortcut{params: shortcut_params}, params) do
    cast(shortcut_params, params, [])
  end

  def cast(%Filter{params: filter_params}, params) do
    cast(filter_params, params, [])
  end

  defp cast([], _params, acc), do: Enum.reverse(acc)

  defp cast([%Param{type: :table, name: name}|automator_params], params, acc) do
    cast(automator_params, params, [{name, to_list(params[name])}|acc])
  end

  defp cast([%Param{type: :account_name, name: name}|automator_params], params, acc) when not is_map_key(params, name) do
    cast(automator_params, params, [{name, nil}|acc])
  end

  defp cast([%Param{type: :account_name, name: name}|automator_params], params, acc) do
    cast(automator_params, params, [{name, String.split(params[name], ".")}|acc])
  end

  defp cast([%Param{type: :string, name: name}|automator_params], params, acc) do
    cast(automator_params, params, [{name, params[name]}|acc])
  end

  defp cast([%Param{type: type, name: name}|automator_params], params, acc) when type in [:money, :integer] do
    value = params[name]
    cond do
      is_integer(value) ->
        cast(automator_params, params, [{name, value}|acc])

      is_float(value) ->
        cast(automator_params, params, [{name, ceil(value * 100)}|acc])

      is_binary(value) and match?({_, ""}, Integer.parse(value)) ->
        cast(automator_params, params, [{name, String.to_integer(value)}|acc])

      :else ->
        cast(automator_params, params, [{name, nil}|acc])
    end
  end

  defp cast([%Param{type: :currency, name: name}|automator_params], params, acc) do
    currencies =
      Money.Currency.all()
      |> Map.keys()
      |> Enum.map(&to_string/1)

    if params[name] in currencies do
      cast(automator_params, params, [{name, String.to_atom(params[name])}|acc])
    else
      cast(automator_params, params, [{name, nil} | acc])
    end
  end

  defp cast([%Param{type: :options, name: name, options: options}|automator_params], params, acc) do
    if params[name] in options do
      cast(automator_params, params, [{name, params[name]}|acc])
    else
      cast(automator_params, params, [{name, nil}|acc])
    end
  end

  defp cast([%Param{type: :date, name: name}|automator_params], params, acc) do
    value = params[name] || ""
    case Date.from_iso8601(value) do
      {:ok, _date} -> cast(automator_params, params, [{name, value}|acc])
      {:error, _} -> cast(automator_params, params, [{name, nil}|acc])
    end
  end
end
