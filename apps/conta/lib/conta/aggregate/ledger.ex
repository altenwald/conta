defmodule Conta.Aggregate.Ledger do
  require Logger

  alias Conta.Aggregate.Ledger.Account

  alias Conta.Command.AccountTransaction
  alias Conta.Command.SetAccount
  alias Conta.Command.SetShortcut

  alias Conta.Event.AccountCreated
  alias Conta.Event.AccountModified
  alias Conta.Event.AccountRenamed
  alias Conta.Event.ShortcutSet
  alias Conta.Event.TransactionCreated

  defstruct name: nil,
            accounts: %{},
            account_names: %{},
            shortcuts: MapSet.new()

  @valid_currencies ~w[EUR USD SEK GBP]a

  def execute(_ledger, %SetAccount{currency: currency})
      when currency not in @valid_currencies do
    {:error, :invalid_currency}
  end

  def execute(_ledger, %SetAccount{ledger: nil}) do
    {:error, :missing_ledger}
  end

  # new account
  def execute(%__MODULE__{} = ledger, %SetAccount{id: nil} = command) do
    cond do
      # account name exists
      account_id = ledger.account_names[command.name] ->
        # transform to update
        execute(ledger, %SetAccount{command | id: account_id})

      not valid_parent?(command.name, ledger) ->
        {:error, :invalid_parent_account}

      :else ->
        command
        |> Map.take(~w[name type currency notes ledger]a)
        |> Map.put(:id, Ecto.UUID.generate())
        |> AccountCreated.changeset()
    end
  end

  # update account
  def execute(%__MODULE__{} = ledger, %SetAccount{} = command) do
    cond do
      account = ledger.accounts[command.id] ->
        Logger.info("update existing account #{account.name}")
        account_modified =
          account
          |> Map.from_struct()
          |> Map.merge(Map.take(account, ~w[id ledger name]a))
          |> then(&struct(AccountModified, &1))
        params = Map.from_struct(command)

        [
          if account.name != command.name do
            %AccountRenamed{
              id: command.id,
              prev_name: account.name,
              new_name: command.name,
              ledger: ledger.name
            }
          end,
          if AccountModified.changed_anything?(account_modified, params) do
            AccountModified.changeset(account_modified, params)
          end
        ]
        |> Enum.reject(&is_nil/1)
        |> case do
          [] -> {:error, :no_changes}
          events -> events
        end

      not valid_parent?(command.name, ledger) ->
        {:error, :invalid_parent_account}

      # id wasn't found
      :else ->
        # convert to create
        execute(ledger, %SetAccount{command | id: nil})
    end
  end

  def execute(_ledger, %AccountTransaction{entries: entries}) when length(entries) < 2 do
    {:error, :not_enough_entries}
  end

  def execute(
        %__MODULE__{} = ledger,
        %AccountTransaction{entries: entries} = transaction
      ) do
    cond do
      not valid_date?(transaction.on_date) ->
        {:error, :invalid_date}

      not valid_entries?(entries, ledger) ->
        {:error, :invalid_entries}

      not valid_accounts?(entries, ledger) ->
        {:error, :invalid_account}

      :else ->
        {entries, _accounts} =
          Enum.map_reduce(transaction.entries, ledger, fn entry, ledger ->
            ledger = update_ledger(ledger, entry)
            account_id = ledger.account_names[entry.account_name]
            account = ledger.accounts[account_id]
            currency = account.currency

            entry =
              entry
              |> Map.take(
                ~w[description account_name credit debit change_currency change_credit change_debit change_price]a
              )
              |> Map.put(:balance, account.balances[currency])
              |> Map.put(:currency, currency)
              |> then(&struct!(TransactionCreated.Entry, &1))

            {entry, ledger}
          end)

        %TransactionCreated{
          id: Ecto.UUID.generate(),
          ledger: transaction.ledger,
          on_date: to_date(transaction.on_date),
          entries: entries
        }
    end
  end

  def execute(_ledger, %SetShortcut{} = command) do
    command
    |> Map.from_struct()
    |> Map.update!(:params, fn params ->
      Enum.map(params, &Map.from_struct/1)
    end)
    |> ShortcutSet.changeset()
  end

  defp update_ledger(ledger, entry) do
    account_id = ledger.account_names[entry.account_name]

    accounts =
      Map.update!(ledger.accounts, account_id, fn account ->
        Map.update!(account, :balances, fn balances ->
          amount = get_amount(to_string(account.type), entry.debit, entry.credit)
          Map.update(balances, account.currency, amount, &(&1 + amount))
        end)
      end)

    %__MODULE__{ledger | accounts: accounts}
  end

  defp to_date(date) when is_struct(date, Date), do: date

  defp to_date(date) when is_binary(date) do
    Date.from_iso8601!(date)
  end

  defp valid_date?(date) when is_struct(date, Date), do: true

  defp valid_date?(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp valid_entries?(entries, ledger) when is_list(entries) do
    Enum.reduce(entries, %{}, fn entry, acc ->
      account_id = ledger.account_names[entry.account_name]
      account = ledger.accounts[account_id]
      balance = entry.debit - entry.credit
      change_balance = entry.change_debit - entry.change_credit

      acc
      |> Map.update(to_string(account.currency), balance, &(&1 + balance))
      |> Map.update(to_string(entry.change_currency), change_balance, &(&1 + change_balance))
    end)
    |> Map.values()
    |> Enum.all?(&(&1 == 0))
  end

  defp valid_accounts?(entries, ledger) when is_list(entries) do
    Enum.all?(entries, &is_map_key(ledger.account_names, &1.account_name))
  end

  defp valid_parent?(account_name, ledger) when is_list(account_name) do
    case Enum.split(account_name, -1) do
      {[], _} -> true
      {parent, _} -> is_map_key(ledger.account_names, parent)
    end
  end

  def apply(%__MODULE__{} = ledger, %AccountModified{} = event) do
    params = Map.take(event, ~w[id type currency notes]a)
    account = struct(ledger.accounts[event.id], params)
    accounts = Map.put(ledger.accounts, account.id, account)
    %__MODULE__{ledger | accounts: accounts}
  end

  def apply(%__MODULE__{} = ledger, %AccountRenamed{} = event) do
    prev_account_names =
      [event.prev_name | search_children(ledger, event.prev_name)]
      |> Enum.sort_by(&length/1, :desc)

    {new_accounts, ledger} =
      prev_account_names
      |> Enum.reduce({[], ledger}, fn prev_account_name, {new_accounts, ledger} ->
        account_id = ledger.account_names[prev_account_name]
        account = ledger.accounts[account_id]
        ledger = remove_account(ledger, account)

        new_account_name = change_parent(prev_account_name, event.prev_name, event.new_name)
        new_account = %Account{account | name: new_account_name}

        {[new_account|new_accounts], ledger}
      end)

    Enum.reduce(new_accounts, ledger, &add_account(&2, &1))
  end

  def apply(%__MODULE__{} = ledger, %AccountCreated{} = event) do
    account =
      event
      |> Map.take(~w[id name type currency notes]a)
      |> then(&struct!(Account, &1))

    add_account(ledger, account)
  end

  def apply(%__MODULE__{} = ledger, %TransactionCreated{entries: entries}) do
    Enum.reduce(entries, ledger, &update_account_balance(&2, &1))
  end

  def apply(%__MODULE__{shortcuts: shortcuts} = ledger, %ShortcutSet{name: name}) do
    %__MODULE__{ledger | shortcuts: MapSet.put(shortcuts, name)}
  end

  defp update_account_hierarchy(ledger, [], _enum_data, _f), do: ledger

  defp update_account_hierarchy(ledger, account_name, enum_data, f) do
    {parent_account_name, _} = Enum.split(account_name, -1)

    Enum.reduce(enum_data, ledger, fn data, ledger ->
      account_id = ledger.account_names[account_name]
      accounts = Map.update!(ledger.accounts, account_id, &f.(&1, data))
      %__MODULE__{ledger | accounts: accounts}
    end)
    |> update_account_hierarchy(parent_account_name, enum_data, f)
  end

  defp search_children(ledger, account_name) do
    ledger.account_names
    |> Map.keys()
    |> Enum.filter(&child?(&1, account_name))
  end

  defp child?(child_name, parent_name) do
    List.starts_with?(child_name, parent_name) and child_name != parent_name
  end

  defp change_parent(account_name, prev_parent, new_parent) do
    new_parent ++ Enum.drop(account_name, length(prev_parent))
  end

  defp remove_account(ledger, account) do
    ledger =
      ledger
      |> search_children(account.name)
      |> Enum.reduce(ledger, &remove_account(&2, &1))
      |> update_account_hierarchy(
        account.name,
        account.balances,
        fn account, {currency, amount} ->
          balances = Map.update(account.balances, currency, amount, &(&1 - amount))
          %Account{account | balances: balances}
        end
      )

    accounts = Map.delete(ledger.accounts, account.id)
    account_names = Map.delete(ledger.account_names, account.name)
    %__MODULE__{ledger | accounts: accounts, account_names: account_names}
  end

  defp add_account(ledger, account) do
    current_account_id = account.id
    accounts = Map.put_new(ledger.accounts, account.id, account)
    account_names = Map.put_new(ledger.account_names, account.name, account.id)

    ledger =
      %__MODULE__{ledger | accounts: accounts, account_names: account_names}
      |> update_account_hierarchy(
        account.name,
        account.balances,
        fn account, {currency, amount} ->
          if current_account_id != account.id do
            balances = Map.update(account.balances, currency, amount, &(&1 + amount))
            %Account{account | balances: balances}
          else
            account
          end
        end
      )

    account_names = Map.put(ledger.account_names, account.name, account.id)
    %__MODULE__{ledger | account_names: account_names}
  end

  defp update_account_balance(ledger, entry) do
    account_id = ledger.account_names[entry.account_name]
    account = ledger.accounts[account_id]
    balance = get_amount(to_string(account.type), entry.debit, entry.credit)

    update_account_hierarchy(
      ledger,
      entry.account_name,
      %{entry.currency => balance},
      fn account, {currency, amount} ->
        balances = Map.update(account.balances, currency, amount, &(&1 + amount))
        %Account{account | balances: balances}
      end
    )
  end

  defp get_amount("assets", debit, credit), do: debit - credit
  defp get_amount("liabilities", debit, credit), do: credit - debit
  defp get_amount("expenses", debit, credit), do: debit - credit
  defp get_amount("revenue", debit, credit), do: credit - debit
  defp get_amount("equity", debit, credit), do: credit - debit
  defp get_amount("", debit, credit), do: credit - debit
end
