defmodule Conta.Projector.Ledger do
  use Commanded.Projections.Ecto,
    application: Conta.Commanded.Application,
    repo: Conta.Repo,
    name: __MODULE__

  import Ecto.Query, only: [from: 2]

  alias Conta.Event.AccountCreated
  alias Conta.Event.AccountModified
  alias Conta.Event.AccountRenamed
  alias Conta.Event.ShortcutSet
  alias Conta.Event.TransactionCreated

  alias Conta.Projector.Ledger.Account
  alias Conta.Projector.Ledger.Balance
  alias Conta.Projector.Ledger.Entry
  alias Conta.Projector.Ledger.Shortcut

  alias Conta.Repo

  project(%AccountCreated{} = account, _metadata, fn multi ->
    parent_id =
      case Enum.split(account.name, -1) do
        {[], _} ->
          nil

        {parent_name, _} ->
          Conta.Repo.get_by!(Account, name: parent_name, ledger: account.ledger).id
      end

    changeset =
      Account.changeset(%{
        id: account.id,
        notes: account.notes,
        parent_id: parent_id,
        name: account.name,
        type: account.type,
        ledger: account.ledger,
        currency: account.currency
      })

    update = [set: [
      notes: account.notes,
      parent_id: parent_id,
      type: account.type,
      currency: account.currency
    ]]

    opts = [
      on_conflict: update,
      conflict_target: [:name, :ledger]
    ]

    Ecto.Multi.insert(multi, :create_account, changeset, opts)
  end)

  project(%AccountModified{} = event, _metadata, fn multi ->
    account = Repo.get!(Account, event.id)
    params = Map.from_struct(event)
    changeset = Account.changeset(account, params)
    Ecto.Multi.update(multi, :account_modified, changeset)
  end)

  project(%AccountRenamed{} = event, _metadata, fn multi ->
    account =
      Repo.get!(Account, event.id)
      |> Repo.preload([:parent, :balances])

    {parent_name, _} = Enum.split(event.new_name, -1)
    multi =
      if parent_name != [] do
        parent = Repo.get_by!(Account, name: parent_name)
        changeset = Account.changeset(account, %{parent_id: parent.id, name: event.new_name})
        add = &update_account_balance(&2, :add, &1, parent)

        Enum.reduce(account.balances, multi, add)
        |> Ecto.Multi.update(:update_account, changeset)
      else
        account = Account.changeset(account, %{parent_id: nil, name: event.new_name})
        Ecto.Multi.update(multi, :update_account, account)
      end

    subtract = &update_account_balance(&2, :subtract, &1, account.parent)
    Enum.reduce(account.balances, multi, subtract)
  end)

  project(%TransactionCreated{} = transaction, _metadata, fn multi ->
    entries_len = length(transaction.entries)
    accounts =
      from(a in Account, select: {a.name, %{id: a.id, type: a.type}})
      |> Repo.all()
      |> Map.new()

    transaction.entries
    |> Enum.with_index(1)
    |> Enum.reduce(multi, fn {trans_entry, idx}, multi ->
      {breakdown, related_account_id} =
        if entries_len > 2 do
          {true, nil}
        else
          [related_entry] = transaction.entries -- [trans_entry]
          {false, related_entry.account_name}
        end

      entry =
        %Entry{
          on_date: to_date(transaction.on_date),
          transaction_id: transaction.id,
          description: trans_entry.description,
          credit: trans_entry.credit,
          debit: trans_entry.debit,
          balance: trans_entry.balance,
          account_name: trans_entry.account_name,
          breakdown: breakdown,
          related_account_name: related_account_id
        }

      multi
      |> upsert_account_balances(idx, accounts, trans_entry)
      |> Ecto.Multi.insert({:entry, idx}, entry)
    end)
  end)

  project(%ShortcutSet{} = event, _metadata, fn multi ->
    if shortcut = Repo.get_by(Shortcut, name: event.name, ledger: event.ledger) do
      changeset = Shortcut.changeset(shortcut, Map.from_struct(event))
      Ecto.Multi.update(multi, :shortcut_update, changeset)
    else
      data = Shortcut.changeset(Map.from_struct(event))
      Ecto.Multi.insert(multi, :shortcut_create, data)
    end
  end)

  defp account_names(account_name) do
    Enum.reduce((1..(length(account_name) - 1)//1), [account_name], fn idx, acc ->
      {parent, _} = Enum.split(account_name, -idx)
      [parent | acc]
    end)
  end

  defp update_account_balance(multi, _type, _balance, nil), do: multi

  defp update_account_balance(multi, type, balance, account) do
    parent_account = Repo.preload(account, :parent).parent
    name = {:account_balance_update, type, account.id}
    query = from(b in Balance, where: b.account_id == ^account.id and b.currency == ^balance.currency)
    updates = [inc: [amount: -balance.amount.amount]]

    multi
    |> Ecto.Multi.update_all(name, query, updates)
    |> update_account_balance(type, balance, parent_account)
  end

  defp upsert_account_balances(multi, idx, accounts, trans_entry) do
    trans_entry.account_name
    |> account_names()
    |> Enum.reduce(multi, fn account_name, multi ->
      account = accounts[account_name]
      amount =
        if account.type in ~w[assets expenses]a do
          trans_entry.debit - trans_entry.credit
        else
          trans_entry.credit - trans_entry.debit
        end

      balance = %Balance{
        account_id: account.id,
        currency: trans_entry.currency,
        amount: amount
      }

      Ecto.Multi.insert(
        multi,
        {:account, idx, account_name},
        balance,
        on_conflict: [inc: [amount: amount]],
        conflict_target: ~w[account_id currency]
      )
    end)
  end

  defp to_date(date) when is_struct(date, Date), do: date

  defp to_date(date) when is_binary(date) do
    Date.from_iso8601!(date)
  end
end
