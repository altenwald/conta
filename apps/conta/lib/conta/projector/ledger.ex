defmodule Conta.Projector.Ledger do
  use Conta.Projector,
    application: Conta.Commanded.Application,
    repo: Conta.Repo,
    name: __MODULE__,
    consistency: Application.compile_env(:conta, :consistency, :eventual)

  import Ecto.Query, only: [from: 2, dynamic: 2]

  require Logger

  alias Conta.Event.AccountCreated
  alias Conta.Event.AccountModified
  alias Conta.Event.AccountRemoved
  alias Conta.Event.AccountRenamed
  alias Conta.Event.TransactionCreated
  alias Conta.Event.TransactionRemoved

  alias Conta.Projector.Ledger.Account
  alias Conta.Projector.Ledger.Balance
  alias Conta.Projector.Ledger.Entry

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

    update = [
      set: [
        notes: account.notes,
        parent_id: parent_id,
        type: account.type,
        currency: account.currency
      ]
    ]

    opts = [
      on_conflict: update,
      conflict_target: [:name, :ledger]
    ]

    Ecto.Multi.insert(multi, :create_account, changeset, opts)
  end)

  project(%AccountRemoved{} = event, _metadata, fn multi ->
    account = Repo.get_by!(Account, ledger: event.ledger, name: event.name)
    Ecto.Multi.delete(multi, :account_removed, account)
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
          b in Balance,
          as: :balance,
          join: a in assoc(b, :account),
          as: :account,
          where: ^get_acc_name_cond(event.prev_name, balance.currency),
          update: [inc: [amount: ^Money.neg(balance.amount)]]
        )

      rename_accounts_query =
        from(
          a in Account,
          where: fragment("?[:?]", a.name, ^length(event.prev_name)) == ^event.prev_name,
          update: [
            set: [name: fragment("? || ?[?:]", ^event.new_name, a.name, ^(length(event.prev_name) + 1))]
          ]
        )

      new_query =
        from(
          b in Balance,
          as: :balance,
          join: a in assoc(b, :account),
          as: :account,
          where: ^get_acc_name_cond(event.new_name, balance.currency),
          update: [inc: [amount: ^balance.amount]]
        )

      rename_entries_query =
        from(
          e in Entry,
          where: fragment("?[:?]", e.account_name, ^length(event.prev_name)) == ^event.prev_name,
          update: [
            set: [
              account_name:
                fragment("? || ?[?:]", ^event.new_name, e.account_name, ^(length(event.prev_name) + 1))
            ]
          ]
        )

      rename_related_entries_query =
        from(
          e in Entry,
          where: fragment("?[:?]", e.related_account_name, ^length(event.prev_name)) == ^event.prev_name,
          update: [
            set: [
              related_account_name:
                fragment(
                  "? || ?[?:]",
                  ^event.new_name,
                  e.related_account_name,
                  ^(length(event.prev_name) + 1)
                )
            ]
          ]
        )

      multi
      |> Ecto.Multi.update_all({:rem_balances, event.new_name, balance}, prev_query, [])
      |> Ecto.Multi.update_all({:rename_accounts, event.new_name, balance}, rename_accounts_query, [])
      |> Ecto.Multi.update_all({:add_balances, event.new_name, balance}, new_query, [])
      |> Ecto.Multi.update_all({:rename_entries, event.new_name, balance}, rename_entries_query, [])
      |> Ecto.Multi.update_all(
        {:rename_related_entries, event.new_name, balance},
        rename_related_entries_query,
        []
      )
    end)
    |> Ecto.Multi.update(
      {:change_parent, event.new_name},
      Account.changeset(account, %{parent_id: new_parent.id})
    )
  end)

  project(%TransactionCreated{} = transaction, _metadata, fn multi ->
    entries_len = length(transaction.entries)

    accounts =
      from(a in Account, select: {a.name, %{id: a.id, currency: a.currency, type: a.type}})
      |> Repo.all()
      |> Map.new()

    transaction.entries
    |> Enum.with_index(1)
    |> Enum.reduce(multi, fn {%TransactionCreated.Entry{} = trans_entry, idx}, multi ->
      {breakdown, related_account_id} =
        if entries_len > 2 do
          {true, nil}
        else
          [related_entry] = transaction.entries -- [trans_entry]
          {false, related_entry.account_name}
        end

      on_date = to_date(transaction.on_date)
      account = accounts[trans_entry.account_name]
      amount = get_amount(account.type, trans_entry.credit, trans_entry.debit)

      balance =
        from(
          e in Entry,
          where: e.on_date <= ^on_date and e.account_name == ^trans_entry.account_name,
          order_by: [desc: e.on_date, desc: e.updated_at],
          limit: 1,
          select: e.balance
        )
        |> Repo.one()
        |> case do
          nil -> Money.new(0)
          balance -> balance
        end

      Logger.debug("previous balance #{inspect(balance)}")

      entry =
        %Entry{
          on_date: on_date,
          transaction_id: transaction.id,
          description: trans_entry.description,
          credit: trans_entry.credit,
          debit: trans_entry.debit,
          balance: Money.add(balance, amount),
          account_name: trans_entry.account_name,
          breakdown: breakdown,
          related_account_name: related_account_id,
          change_currency: trans_entry.change_currency,
          change_credit: trans_entry.change_credit,
          change_debit: trans_entry.change_debit
        }

      updated_at = NaiveDateTime.utc_now()

      multi
      |> upsert_account_balances(idx, accounts, account.currency, trans_entry)
      |> update_entry_balances(idx, trans_entry.account_name, on_date, updated_at, amount)
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
      account = accounts[entry.account_name]
      amount = get_amount(account.type, entry.credit, entry.debit)

      multi
      |> remove_account_balances(accounts, entry)
      |> update_entry_balances(
        entry.id,
        entry.account_name,
        entry.on_date,
        entry.updated_at,
        Money.neg(amount)
      )
      |> Ecto.Multi.delete({:remove_entry, entry.id}, entry)
    end)
  end)

  @impl Conta.Projector
  def after_update(%AccountCreated{ledger: ledger}, _metadata, changes) do
    event_name = "event:account_created:#{ledger}"
    Phoenix.PubSub.broadcast(Conta.PubSub, event_name, %{id: changes.create_account.id})
  end

  def after_update(%AccountModified{}, _metadata, changes) do
    event_name = "event:account_modified:#{changes.account_modified.ledger}"
    Phoenix.PubSub.broadcast(Conta.PubSub, event_name, %{id: changes.account_modified.id})
  end

  def after_update(%AccountRemoved{}, _metadata, changes) do
    event_name = "event:account_removed:#{changes.account_removed.ledger}"
    Phoenix.PubSub.broadcast(Conta.PubSub, event_name, %{id: changes.account_removed.id})
  end

  def after_update(%TransactionCreated{}, _metadata, changes) do
    changes
    |> Enum.filter(fn {key, _} -> match?({:entry, _idx}, key) end)
    |> Enum.map(fn {_, entry} -> {Enum.join(entry.account_name, "."), entry.transaction_id} end)
    |> Enum.uniq()
    |> Enum.each(fn {account_name, transaction_id} ->
      event_name = "event:transaction_created:#{account_name}"
      Logger.debug("sending broadcast for event #{inspect(event_name)}")
      Phoenix.PubSub.broadcast(Conta.PubSub, event_name, %{id: transaction_id})
    end)
  end

  def after_update(%TransactionRemoved{}, _metadata, changes) do
    changes
    |> Map.keys()
    |> Enum.filter(&match?({:remove_account_balance, _, _}, &1))
    |> Enum.each(fn {:remove_account_balance, entry_id, account_name} ->
      event_name = "event:transaction_removed:#{Enum.join(account_name, ".")}"
      Phoenix.PubSub.broadcast(Conta.PubSub, event_name, %{id: entry_id})
    end)
  end

  def after_update(_event, _metadata, _changes), do: :ok

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
    Enum.reduce(1..(length(account_name) - 1)//1, [account_name], fn idx, acc ->
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

  defp get_amount(type, %Money{} = credit, %Money{} = debit)
       when type in ~w[assets expenses]a,
       do: Money.subtract(debit, credit)

  defp get_amount(_type, %Money{} = credit, %Money{} = debit),
    do: Money.subtract(credit, debit)

  defp get_amount(type, credit, debit)
       when type in ~w[assets expenses]a and
              is_integer(credit) and
              is_integer(debit),
       do: debit - credit

  defp get_amount(_type, credit, debit)
       when is_integer(credit) and is_integer(debit),
       do: credit - debit

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

  defp update_entry_balances(multi, entry_id, account_name, on_date, updated_at, amount) do
    query =
      from(
        e in Entry,
        where: e.account_name == ^account_name,
        where: e.on_date > ^on_date or (e.on_date == ^on_date and e.updated_at > ^updated_at)
      )

    Logger.debug(
      "adding amount #{inspect(amount)} greater than or equal to #{on_date}" <>
        " and greater than #{updated_at} for #{Enum.join(account_name, ".")}"
    )

    updates = [inc: [balance: amount]]

    Ecto.Multi.update_all(multi, {:update_newer_entries_balances, entry_id}, query, updates)
  end
end
