defmodule Conta.Automator do
  require Logger

  import Conta.Commanded.Application, only: [dispatch: 1]
  import Ecto.Query, only: [from: 2]

  alias Conta.Command.RemoveShortcut
  alias Conta.Command.SetAccountTransaction
  alias Conta.Command.SetInvoice
  alias Conta.Command.SetShortcut
  alias Conta.Projector.Automator.Shortcut
  alias Conta.Projector.Automator.ShortcutParam
  alias Conta.Repo

  def list_shortcuts(automator \\ "default") do
    from(
      s in Shortcut,
      where: s.automator == ^automator,
      order_by: s.name
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

  def get_set_shortcut(id) when is_binary(id),
    do: get_set_shortcut(get_shortcut!(id))

  def get_set_shortcut(%Shortcut{} = shortcut) do
    %SetShortcut{
      name: shortcut.name,
      automator: shortcut.automator,
      params: for %ShortcutParam{} = shortcut_param <- shortcut.params do
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

  def get_shortcut_by_name(automator \\ "default", name) do
    Repo.get_by(Shortcut, name: name, automator: automator)
  end

  def get_shortcut(automator \\ "default", id) do
    Repo.get_by(Shortcut, id: id, automator: automator)
  end

  def get_shortcut!(automator \\ "default", id) do
    Repo.get_by!(Shortcut, id: id, automator: automator)
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
         {:ok, [result]} when is_list(result) <- run(shortcut.code, params),
         %{"status" => "ok", "data" => data} = return <- Map.new(result) do
      Logger.debug("received data from Lua script: #{inspect(data)}")
      data = process_data(data)
      case return["type"] || "transaction" do
        "transaction" ->
          data
          |> SetAccountTransaction.changeset()
          |> Conta.EctoHelpers.get_result()
          |> case do
            %SetAccountTransaction{} = command ->
              Logger.debug("processing command: #{inspect(command)}")
              dispatch(command)

            {:error, _} = error ->
              error
          end

        "invoice" ->
          data
          |> SetInvoice.changeset()
          |> Conta.EctoHelpers.get_result()
          |> case do
            %SetInvoice{} = command ->
              Logger.debug("processing command: #{inspect(command)}")
              dispatch(command)

            {:error, _} = error ->
              error
          end
      end
    else
      {:error, _} = error -> error
      {:ok, return} -> {:error, {:invalid_code_return, return}}
      {:error, compile, _stacktrace} -> {:error, compile}
      %{} = return -> {:error, {:invalid_code_return, return}}
    end
  end

  defp process_data(data) do
    cond do
      not is_list(data) ->
        data

      Enum.all?(data, fn {k, _} -> is_integer(k) end) ->
        Enum.map(data, fn {_, value} -> process_data(value) end)

      :else ->
        Map.new(data, fn {k, v} -> {k, process_data(v)} end)
    end
  end

  defp run(code, params) do
    params
    |> Enum.reduce(:luerl.init(), fn {name, value}, state ->
      :luerl.set_table([name], value, state)
    end)
    ### XXX: we have to use here charlist because binary breaks the collation.
    |> then(&:luerl.eval(to_charlist(code), &1))
  end

  defp validate_params([], _params), do: :ok

  defp validate_params([%ShortcutParam{name: name}|_], params) when not is_map_key(params, name) do
    {:error, %{name => ["can't be blank"]}}
  end

  defp validate_params([%ShortcutParam{type: :account_name} = param|short_params], params) do
    param_value = params[param.name]
    if is_list(param_value) and Enum.all?(param_value, &is_binary/1) do
      validate_params(short_params, params)
    else
      {:error, %{param.name => ["is invalid"]}}
    end
  end

  defp validate_params([%ShortcutParam{type: :string} = param|short_params], params) do
    if is_binary(params[param.name]) do
      validate_params(short_params, params)
    else
      {:error, %{param.name => ["is invalid"]}}
    end
  end

  defp validate_params([%ShortcutParam{type: type} = param|short_params], params) when type in [:money, :integer] do
    if is_integer(params[param.name]) or match?({_, ""}, Integer.parse(params[param.name])) do
      validate_params(short_params, params)
    else
      {:error, %{param.name => ["is invalid"]}}
    end
  end

  defp validate_params([%ShortcutParam{type: :currency} = param|short_params], params) do
    currencies =
      Money.Currency.all()
      |> Map.keys()
      |> Enum.map(&to_string/1)

    if params[param.name] in currencies do
      validate_params(short_params, params)
    else
      {:error, %{param.name => ["is invalid"]}}
    end
  end

  defp validate_params([%ShortcutParam{type: :options} = param|short_params], params) do
    if params[param.name] in param.options do
      validate_params(short_params, params)
    else
      {:error, %{param.name => ["is invalid"]}}
    end
  end

  defp validate_params([%ShortcutParam{type: :date} = param|short_params], params) do
    value = params[param.name]
    cond do
      is_struct(value, Date) ->
        validate_params(short_params, params)

      is_binary(value) and Date.from_iso8601(value) ->
        validate_params(short_params, params)

      :else ->
        {:error, %{param.name => ["is invalid"]}}
    end
  end

  def cast(%Shortcut{params: shortcut_params}, params) do
    cast(shortcut_params, params, [])
  end

  defp cast([], _params, acc), do: Enum.reverse(acc)

  defp cast([%ShortcutParam{type: :account_name, name: name}|shortcut_params], params, acc) when not is_map_key(params, name) do
    cast(shortcut_params, params, [{name, nil}|acc])
  end

  defp cast([%ShortcutParam{type: :account_name, name: name}|shortcut_params], params, acc) do
    cast(shortcut_params, params, [{name, String.split(params[name], ".")}|acc])
  end

  defp cast([%ShortcutParam{type: :string, name: name}|shortcut_params], params, acc) do
    cast(shortcut_params, params, [{name, params[name]}|acc])
  end

  defp cast([%ShortcutParam{type: type, name: name}|shortcut_params], params, acc) when type in [:money, :integer] do
    case Integer.parse(params[name]) do
      {number, _} -> cast(shortcut_params, params, [{name, number}|acc])
      _ -> cast(shortcut_params, params, [{name, nil}|acc])
    end
  end

  defp cast([%ShortcutParam{type: :currency, name: name}|shortcut_params], params, acc) do
    currencies =
      Money.Currency.all()
      |> Map.keys()
      |> Enum.map(&to_string/1)

    if params[name] in currencies do
      cast(shortcut_params, params, [{name, String.to_atom(params[name])}|acc])
    else
      cast(shortcut_params, params, [{name, nil} | acc])
    end
  end

  defp cast([%ShortcutParam{type: :options, name: name, options: options}|shortcut_params], params, acc) do
    if params[name] in options do
      cast(shortcut_params, params, [{name, params[name]}|acc])
    else
      cast(shortcut_params, params, [{name, nil}|acc])
    end
  end

  defp cast([%ShortcutParam{type: :date, name: name}|shortcut_params], params, acc) do
    case Date.from_iso8601(params[name]) do
      {:ok, date} -> cast(shortcut_params, params, [{name, date}|acc])
      {:error, _} -> cast(shortcut_params, params, [{name, nil}|acc])
    end
  end
end
