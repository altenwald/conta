defmodule Conta.Aggregate.Ledger do
  alias Conta.Aggregate.Ledger.Account

  alias Conta.Command.AccountTransaction
  alias Conta.Command.CreateAccount

  alias Conta.Event.AccountCreated
  alias Conta.Event.TransactionCreated

  defstruct name: nil, accounts: %{}

  @valid_currencies ~w[EUR USD SEK GBP]a

  def execute(_ledger, %CreateAccount{currency: currency}) when currency not in @valid_currencies do
    {:error, :invalid_currency}
  end

  def execute(_ledger, %CreateAccount{ledger: nil}) do
    {:error, :missing_ledger}
  end

  def execute(%__MODULE__{accounts: accounts}, %CreateAccount{} = command) do
    cond do
      accounts[command.name] != nil ->
        {:error, :duplicate_account_name}

      not valid_parent?(command.name, accounts) ->
        {:error, :invalid_parent_account}

      :else ->
        command
        |> Map.take(~w[name type currency notes ledger]a)
        |> then(&struct!(AccountCreated, &1))
    end
  end

  def execute(_ledger, %AccountTransaction{entries: entries}) when length(entries) < 2 do
    {:error, :not_enough_entries}
  end

  def execute(%__MODULE__{accounts: accounts}, %AccountTransaction{entries: entries} = transaction) do
    cond do
      not valid_date?(transaction.on_date) ->
        {:error, :invalid_date}

      not valid_entries?(entries, accounts) ->
        {:error, :invalid_entries}

      not valid_accounts?(entries, accounts) ->
        {:error, :invalid_account}

      :else ->
        {entries, _accounts} =
          Enum.map_reduce(transaction.entries, accounts, fn entry, acc ->
            accounts =
              Map.update!(acc, entry.account_name, fn account ->
                Map.update!(account, :balances, fn balances ->
                  amount = get_amount(to_string(account.type), entry.debit, entry.credit)
                  Map.update(balances, account.currency, amount, &(&1 + amount))
                end)
              end)

            account = accounts[entry.account_name]
            currency = account.currency

            entry =
              entry
              |> Map.take(~w[description account_name credit debit change_currency change_credit change_debit change_price]a)
              |> Map.put(:balance, account.balances[currency])
              |> Map.put(:currency, currency)
              |> then(&struct!(TransactionCreated.Entry, &1))

            {entry, accounts}
          end)

        %TransactionCreated{
          id: Ecto.UUID.generate(),
          on_date: to_date(transaction.on_date),
          entries: entries
        }
    end
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

  defp valid_entries?(entries, accounts) when is_list(entries) do
    Enum.reduce(entries, %{}, fn entry, acc ->
      account = accounts[entry.account_name]
      balance = entry.debit - entry.credit
      change_balance = entry.change_debit - entry.change_credit

      acc
      |> Map.update(account.currency, balance, & &1 + balance)
      |> Map.update(entry.change_currency, change_balance, & &1 + change_balance)
    end)
    |> Map.values()
    |> Enum.all?(& &1 == 0)
  end

  defp valid_accounts?(entries, accounts) when is_list(entries) do
    Enum.all?(entries, &is_map_key(accounts, &1.account_name))
  end

  defp valid_parent?(account_name, accounts) when is_list(account_name) do
    case Enum.split(account_name, -1) do
      {[], _} -> true
      {parent, _} -> is_map_key(accounts, parent)
    end
  end

  def apply(%__MODULE__{} = ledger, %AccountCreated{} = event) do
    account =
      event
      |> Map.take(~w[name type currency notes]a)
      |> then(&struct!(Account, &1))

    %__MODULE__{
      name: event.ledger,
      accounts: Map.put(ledger.accounts, account.name, account)
    }
  end

  def apply(%__MODULE__{accounts: accounts} = ledger, %TransactionCreated{entries: entries}) do
    accounts = Enum.reduce(entries, accounts, &update_account_balance(&2, &1.account_name, &1))
    %__MODULE__{ledger | accounts: accounts}
  end

  defp update_account_balance(accounts, [], _entry), do: accounts

  defp update_account_balance(accounts, account_name, entry) do
    {parent_account_name, _} = Enum.split(account_name, -1)

    accounts
    |> Map.update!(account_name, fn account ->
      amount = get_amount(to_string(account.type), entry.debit, entry.credit)
      balances = Map.update(account.balances, entry.currency, amount, &(&1 + amount))
      %Account{account | balances: balances}
    end)
    |> update_account_balance(parent_account_name, entry)
  end

  defp get_amount("assets", debit, credit), do: debit - credit
  defp get_amount("liabilities", debit, credit), do: credit - debit
  defp get_amount("expenses", debit, credit), do: debit - credit
  defp get_amount("revenue", debit, credit), do: credit - debit
  defp get_amount("equity", debit, credit), do: credit - debit
  defp get_amount("", debit, credit), do: credit - debit
end
