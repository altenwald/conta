defmodule Conta.Ledger do
  import Conta.Commanded.Application
  import Ecto.Query, only: [from: 2]

  alias Conta.Command.SetAccount
  alias Conta.Command.SetAccountTransaction
  alias Conta.Command.SetInvoice

  alias Conta.Projector.Ledger.Account
  alias Conta.Projector.Ledger.Entry
  alias Conta.Projector.Ledger.Shortcut
  alias Conta.Projector.Ledger.ShortcutParam
  alias Conta.Repo

  @default_currencies ~w[EUR GBP USD]a

  def set_account(name, type, currency \\ :EUR, notes \\ nil, ledger \\ "default") do
    %SetAccount{name: name, type: type, currency: currency, notes: notes, ledger: ledger}
    |> dispatch()
  end

  def create_account_transaction(on_date, entries, ledger \\ "default") do
    %SetAccountTransaction{ledger: ledger, on_date: on_date, entries: entries}
    |> dispatch()
  end

  def new_account_transaction(account_name, ledger \\ "default") do
    %SetAccountTransaction{
      ledger: ledger,
      on_date: Date.utc_today(),
      entries: [
        %SetAccountTransaction.Entry{account_name: account_name},
        %SetAccountTransaction.Entry{}
      ]
    }
  end

  def entry(description, account_name, credit, debit, change_currency, change_credit, change_debit, change_price) do
    %SetAccountTransaction.Entry{
      description: description,
      account_name: account_name,
      credit: credit,
      debit: debit,
      change_currency: change_currency,
      change_credit: change_credit,
      change_debit: change_debit,
      change_price: change_price
    }
  end

  def get_account_by_name(name) when is_list(name) do
    if account = Repo.get_by(Account, name: name) do
      {:ok, account}
    else
      {:error, :invalid_account_name}
    end
  end

  def get_account_command!(id) do
    Repo.get!(Account, id)
    |> Map.from_struct()
    |> then(&struct(SetAccount, &1))
    |> populate_account_virtual()
  end

  def get_account!(id) do
    Repo.get!(Account, id)
    |> Repo.preload(:balances)
  end

  def get_entry!(id) do
    Repo.get!(Entry, id)
  end

  defp populate_account_virtual(account) do
    case List.pop_at(account.name, -1) do
      {simple_name, []} ->
        %SetAccount{account | simple_name: simple_name, parent_name: nil}

      {simple_name, parent_name} ->
        parent_name = Enum.join(parent_name, ".")
        %SetAccount{account | simple_name: simple_name, parent_name: parent_name}
    end
  end

  def list_ledgers do
    from(a in Account, order_by: a.ledger, select: a.ledger, group_by: a.ledger)
    |> Repo.all()
  end

  def list_accounts do
    from(a in Account, order_by: a.name, preload: :balances)
    |> Repo.all()
  end

  def list_accounts(type, depth \\ nil)

  def list_accounts(type, nil) do
    from(a in Account, where: a.type == ^type, preload: :balances)
    |> Repo.all()
  end

  def list_accounts(type, depth) when is_integer(depth) and depth > 0 do
    from(
      a in Account,
      where: a.type == ^type and fragment("array_length(?, 1)", a.name) == ^depth,
      preload: :balances
    )
    |> Repo.all()
  end

  def list_currencies do
    Application.get_env(:conta, :currencies, @default_currencies)
  end

  def list_used_currencies do
    from(a in Account, group_by: a.currency, select: a.currency)
    |> Repo.all()
  end

  def list_accounts_by_parent(nil) do
    from(
      a in Account,
      where: is_nil(a.parent_id),
      order_by: a.name,
      preload: :balances
    )
    |> Repo.all()
  end

  def list_accounts_by_parent(parent) do
    from(
      a in Account,
      join: p in Account,
      on: a.parent_id == p.id,
      where: p.name == ^parent,
      order_by: a.name,
      preload: :balances
    )
    |> Repo.all()
  end

  def list_entries(account_name, limit) when is_list(account_name) and is_integer(limit) do
    if account = Repo.get_by(Account, name: account_name) do
      list_entries_by_account(account, limit)
    end
  end

  def list_entries_by_account(%Account{} = account, limit \\ nil) do
    from(
      e in Entry,
      where: e.account_name == ^account.name,
      order_by: [desc: e.on_date, desc: e.inserted_at]
    )
    |> case do
      query when limit != nil ->
        from(e in query, limit: ^limit)

      query -> query
    end
    |> Repo.all()
    |> Enum.map(&adjust_currency(&1, account.currency))
  end

  def list_entries_by(text, limit) when is_integer(limit) do
    from(
      e in Entry,
      where: fragment("? ~ ?", e.description, ^text),
      or_where: fragment("ARRAY_TO_STRING(?, '.') ~ ?", e.account_name, ^text),
      order_by: [desc: e.on_date],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp adjust_currency(%Entry{} = entry, currency) do
    %Entry{entry |
      credit: Money.new(entry.credit.amount, currency),
      debit: Money.new(entry.debit.amount, currency),
      balance: Money.new(entry.balance.amount, currency)
    }
  end

  def list_shortcuts(ledger \\ "default") do
    from(
      s in Shortcut,
      where: s.ledger == ^ledger,
      order_by: s.name
    )
    |> Repo.all()
  end

  def get_shortcut(ledger \\ "default", name) do
    Repo.get_by(Shortcut, name: name, ledger: ledger)
  end

  def run_shortcut(ledger \\ "default", name, params) do
    with {:shortcut, %Shortcut{} = shortcut} <- {:shortcut, get_shortcut(ledger, name)},
         :ok <- validate_params(shortcut.params, params),
         {:ok, [result]} when is_list(result) <- run(shortcut.code, params),
         %{"status" => "ok", "data" => data} = return <- Map.new(result) do
      data = process_data(data)
      case return["type"] || "transaction" do
        "transaction" ->
          data
          |> SetAccountTransaction.changeset()
          |> Conta.EctoHelpers.traverse_errors()
          |> case do
            %SetAccountTransaction{} = command ->
              dispatch(command)

            {:error, _} = error ->
              error
          end

        "invoice" ->
          data
          |> SetInvoice.changeset()
          |> Conta.EctoHelpers.traverse_errors()
          |> case do
            %SetInvoice{} = command ->
              dispatch(command)

            {:error, _} = error ->
              error
          end
      end
    else
      {:shortcut, nil} -> {:error, :shortcut_not_found}
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
    {:error, {:missing, name}}
  end

  defp validate_params([%ShortcutParam{type: :account_name} = param|short_params], params) do
    param_value = params[param.name]
    if is_list(param_value) and Enum.all?(param_value, &is_binary/1) do
      validate_params(short_params, params)
    else
      {:error, {:invalid, param.name, param_value}}
    end
  end

  defp validate_params([%ShortcutParam{type: :string} = param|short_params], params) do
    if is_binary(params[param.name]) do
      validate_params(short_params, params)
    else
      {:error, {:invalid, param.name, params[param.name]}}
    end
  end

  defp validate_params([%ShortcutParam{type: type} = param|short_params], params) when type in [:money, :integer] do
    if is_integer(params[param.name]) do
      validate_params(short_params, params)
    else
      {:error, {:invalid, param.name, params[param.name]}}
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
      {:error, {:invalid, param.name, params[param.name]}}
    end
  end

  defp validate_params([%ShortcutParam{type: :options} = param|short_params], params) do
    if params[param.name] in param.options do
      validate_params(short_params, params)
    else
      {:error, {:invalid, param.name, params[param.name]}}
    end
  end

  defp validate_params([%ShortcutParam{type: :date} = param|short_params], params) do
    case Date.from_iso8601(params[param.name]) do
      {:ok, _} -> validate_params(short_params, params)
      {:error, _} -> {:error, {:invalid, param.name, params[param.name]}}
    end
  end
end
