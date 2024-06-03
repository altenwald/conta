defmodule Conta.Projector.Ledger do
  use Commanded.Projections.Ecto,
    application: Conta.Commanded.Application,
    repo: Conta.Repo,
    name: __MODULE__

  import Ecto.Query, only: [from: 2, dynamic: 2]

  require Logger

  alias Conta.Event.AccountCreated
  alias Conta.Event.AccountModified
  alias Conta.Event.AccountRenamed
  alias Conta.Event.ShortcutSet
  alias Conta.Event.TransactionCreated
  alias Conta.Event.TransactionRemoved

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
      Account
      |> Repo.get!(event.id)
      |> Repo.preload(:balances)

    new_parent = Repo.get_by!(Account, name: event.new_name |> Enum.reverse() |> tl() |> Enum.reverse())

    Enum.reduce(account.balances, multi, fn balance, multi ->
      prev_query =
        from(
          b in Balance, as: :balance,
          join: a in assoc(b, :account), as: :account,
          where: ^get_acc_name_cond(event.prev_name, balance.currency),
          update: [inc: [amount: ^Money.neg(balance.amount)]]
        )

      rename_accounts_query =
        from(
          a in Account,
          where: fragment("?[:?]", a.name, ^length(event.prev_name)) == ^event.prev_name,
          update: [set: [name: fragment("? || ?[?:]", ^event.new_name, a.name, ^(length(event.prev_name) + 1))]]
        )

      new_query =
        from(
          b in Balance, as: :balance,
          join: a in assoc(b, :account), as: :account,
          where: ^get_acc_name_cond(event.new_name, balance.currency),
          update: [inc: [amount: ^balance.amount]]
        )

      rename_entries_query =
        from(
          e in Entry,
          where: fragment("?[:?]", e.account_name, ^length(event.prev_name)) == ^event.prev_name,
          update: [set: [account_name: fragment("? || ?[?:]", ^event.new_name, e.account_name, ^(length(event.prev_name) + 1))]]
        )

      rename_related_entries_query =
        from(
          e in Entry,
          where: fragment("?[:?]", e.related_account_name, ^length(event.prev_name)) == ^event.prev_name,
          update: [set: [
            related_account_name: fragment("? || ?[?:]", ^event.new_name, e.related_account_name, ^(length(event.prev_name) + 1))
          ]]
        )

      multi
      |> Ecto.Multi.update_all({:rem_balances, event.new_name, balance}, prev_query, [])
      |> Ecto.Multi.update_all({:rename_accounts, event.new_name, balance}, rename_accounts_query, [])
      |> Ecto.Multi.update_all({:add_balances, event.new_name, balance}, new_query, [])
      |> Ecto.Multi.update_all({:rename_entries, event.new_name, balance}, rename_entries_query, [])
      |> Ecto.Multi.update_all({:rename_related_entries, event.new_name, balance}, rename_related_entries_query, [])
    end)
    |> Ecto.Multi.update({:change_parent, event.new_name}, Account.changeset(account, %{parent_id: new_parent.id}))
  end)

  project(%TransactionCreated{} = transaction, _metadata, fn multi ->
    entries_len = length(transaction.entries)
    accounts =
      from(a in Account, select: {a.name, %{id: a.id, currency: a.currency, type: a.type}})
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

      account = accounts[trans_entry.account_name]

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
      |> upsert_account_balances(idx, accounts, account.currency, trans_entry)
      |> Ecto.Multi.insert({:entry, idx}, entry)
    end)
  end)

  project(%TransactionRemoved{id: id}, _metadata, fn multi ->
    accounts =
      from(a in Account, select: {a.name, %{id: a.id, currency: a.currency, type: a.type}})
      |> Repo.all()
      |> Map.new()

    from(a in Entry, where: a.transaction_id == ^id)
    |> Repo.all()
    |> Enum.reduce(multi, fn entry, multi ->
      multi
      |> remove_account_balances(accounts, entry)
      |> Ecto.Multi.delete({:remove_entry, entry.id}, entry)
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

  defp get_acc_name_cond(account_name, currency) do
    [name | names] = account_names(account_name)
    prev_name_cond =
      Enum.reduce(
        names,
        dynamic([account: a], a.name == ^name),
        fn name, conditions ->
          dynamic([account: a], a.name == ^name or ^conditions)
        end
      )

    dynamic([balance: b], b.currency == ^currency and ^prev_name_cond)
  end

  defp account_names(account_name) do
    Enum.reduce((1..(length(account_name) - 1)//1), [account_name], fn idx, acc ->
      {parent, _} = Enum.split(account_name, -idx)
      [parent | acc]
    end)
  end

  defp remove_account_balances(multi, accounts, entry) do
    account = accounts[entry.account_name]
    Logger.debug("searching for account #{inspect(account)} (from #{inspect(entry.account_name)})")
    amount = get_amount(account.type, entry.credit, entry.debit)

    entry.account_name
    |> account_names()
    |> Enum.reduce(multi, fn account_name, multi ->
      account = accounts[account_name]
      Logger.debug("reducing #{inspect(account_name)} #{account.id} reducing #{Money.neg(amount)}")
      query = from(b in Balance, where: b.account_id == ^account.id and b.currency == ^account.currency)
      updates = [inc: [amount: Money.neg(amount)]]
      Ecto.Multi.update_all(multi, {:remove_account_balance, entry.id, account_name}, query, updates)
    end)
  end

  defp get_amount(type, credit, debit) when type in ~w[assets expenses]a, do: Money.subtract(debit, credit)
  defp get_amount(_type, credit, debit), do: Money.subtract(credit, debit)

  defp upsert_account_balances(multi, idx, accounts, currency, trans_entry) do
    trans_entry.account_name
    |> account_names()
    |> Enum.reduce(multi, fn account_name, multi ->
      account = accounts[account_name]
      amount = get_amount(account.type, trans_entry.credit, trans_entry.debit)

      balance = %Balance{
        account_id: account.id,
        currency: currency,
        amount: amount
      }

      Ecto.Multi.insert(
        multi,
        {:upsert_account_balances, idx, account_name},
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
