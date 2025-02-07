defmodule Conta.Ledger do
  import Conta.Commanded.Application
  import Ecto.Query, only: [from: 2]

  alias Conta.Command.RemoveAccount
  alias Conta.Command.RemoveAccountTransaction
  alias Conta.Command.SetAccount
  alias Conta.Command.SetAccountTransaction

  alias Conta.Projector.Ledger.Account
  alias Conta.Projector.Ledger.Entry
  alias Conta.Repo

  @default_frequent_currencies ~w[EUR GBP USD]a

  def set_account(name, type, currency \\ :EUR, notes \\ nil, ledger \\ "default") do
    %SetAccount{name: name, type: type, currency: currency, notes: notes, ledger: ledger}
    |> dispatch()
  end

  def delete_account(name, ledger \\ "default") do
    %RemoveAccount{name: name, ledger: ledger}
    |> dispatch()
  end

  def create_account_transaction(on_date, entries, ledger \\ "default") do
    %SetAccountTransaction{ledger: ledger, on_date: on_date, entries: entries}
    |> dispatch()
  end

  def delete_account_transaction(transaction_id) do
    case get_entries_by_transaction_id(transaction_id) do
      [] ->
        {:error, :transaction_not_found}

      [entry | _] = entries ->
        %RemoveAccountTransaction{
          ledger: "default",
          on_date: entry.on_date,
          transaction_id: transaction_id,
          entries:
            for entry <- entries do
              %RemoveAccountTransaction.Entry{
                account_name: entry.account_name,
                credit: entry.credit,
                debit: entry.debit,
                change_currency: entry.change_currency,
                change_credit: entry.change_credit,
                change_debit: entry.change_debit
              }
            end
        }
        |> dispatch()
    end
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

  def entry(description, account_name, credit, debit, change_currency, change_credit, change_debit) do
    %SetAccountTransaction.Entry{
      description: description,
      account_name: account_name,
      credit: credit,
      debit: debit,
      change_currency: change_currency,
      change_credit: change_credit,
      change_debit: change_debit
    }
  end

  def get_account_by_name(name) when is_list(name) do
    if account = Repo.get_by(Account, name: name) do
      {:ok, Repo.preload(account, :balances)}
    else
      {:error, :invalid_account_name}
    end
  end

  def get_account_by_parent_id(parent_id) do
    from(a in Account, where: a.parent_id == ^parent_id)
    |> Repo.all()
  end

  def get_account_name_chunk_with_id!(account_name) do
    Enum.reduce(1..(length(account_name) - 1)//1, [account_name], fn idx, acc ->
      {parent, _} = Enum.split(account_name, -idx)
      [parent | acc]
    end)
    |> Enum.map(fn name ->
      {:ok, account} = get_account_by_name(name)
      name = name |> Enum.reverse() |> hd()
      {name, account.id}
    end)
  end

  def get_account_command!(id) do
    Repo.get!(Account, id)
    |> Map.from_struct()
    |> then(&struct(SetAccount, &1))
    |> populate_account_virtual()
  end

  def get_account(id) do
    Repo.get(Account, id)
    |> Repo.preload(:balances)
  end

  def get_account!(id) do
    Repo.get!(Account, id)
    |> Repo.preload(:balances)
  end

  def get_entry!(id) do
    Repo.get!(Entry, id)
  end

  def get_entry(id) do
    Repo.get(Entry, id)
  end

  def get_entries_by_transaction_id(transaction_id) do
    from(e in Entry, where: e.transaction_id == ^transaction_id, order_by: e.inserted_at)
    |> Repo.all()
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

  def search_accounts(text) do
    from(
      a in Account,
      where: fragment("POSITION(? IN ARRAY_TO_STRING(?, '.')) > 0", ^text, a.name)
    )
    |> Repo.all()
  end

  def list_accounts do
    from(a in Account, order_by: a.name, preload: :balances)
    |> Repo.all()
  end

  def list_simple_accounts do
    from(a in Account, order_by: a.name)
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
    Application.get_env(:conta, :frequent_currencies, @default_frequent_currencies)
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
      order_by: [desc: e.on_date, desc: e.updated_at]
    )
    |> case do
      query when limit != nil ->
        from(e in query, limit: ^limit)

      query ->
        query
    end
    |> Repo.all()
    |> Enum.map(&adjust_currency(&1, account.currency))
  end

  def list_entries_by_account(%Account{} = account, page, dates_per_page) do
    dates =
      from(
        e in Entry,
        where: e.account_name == ^account.name,
        order_by: [desc: e.on_date],
        group_by: e.on_date,
        select: e.on_date
      )
      |> Repo.all()
      |> Enum.chunk_every(dates_per_page)
      |> Enum.at(page - 1, [])

    from(
      e in Entry,
      where: e.account_name == ^account.name and e.on_date in ^dates,
      order_by: [desc: e.on_date, desc: e.updated_at]
    )
    |> Repo.all()
    |> Enum.map(&adjust_currency(&1, account.currency))
  end

  def search_entries_by_account(%Account{} = account, search, page, dates_per_page) do
    search = "%" <> Regex.replace(~r/^$|([\%_])/, search, "[\\1]") <> "%"

    dates =
      from(
        e in Entry,
        where: e.account_name == ^account.name,
        where: ilike(e.description, ^search),
        order_by: [desc: e.on_date],
        group_by: e.on_date,
        select: e.on_date
      )
      |> Repo.all()
      |> Enum.chunk_every(dates_per_page)
      |> Enum.at(page - 1, [])

    from(
      e in Entry,
      where: e.account_name == ^account.name and e.on_date in ^dates,
      where: ilike(e.description, ^search),
      order_by: [desc: e.on_date, desc: e.updated_at]
    )
    |> Repo.all()
    |> Enum.map(&adjust_currency(&1, account.currency))
  end

  def list_entries_by(text, limit) when is_integer(limit) do
    from(
      e in Entry,
      where: fragment("? ~ ?", e.description, ^text),
      or_where: fragment("ARRAY_TO_STRING(?, '.') ~ ?", e.account_name, ^text),
      order_by: [desc: e.on_date, desc: e.updated_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp adjust_currency(%Entry{} = entry, currency) do
    %Entry{
      entry
      | credit: Money.new(entry.credit.amount, currency),
        debit: Money.new(entry.debit.amount, currency),
        balance: Money.new(entry.balance.amount, currency)
    }
  end
end
