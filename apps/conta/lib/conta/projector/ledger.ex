defmodule Conta.Projector.Ledger do
  use Commanded.Projections.Ecto,
    application: Conta.Commanded.Application,
    repo: Conta.Repo,
    name: __MODULE__

  import Ecto.Query, only: [from: 2]

  alias Conta.Event.AccountSet
  alias Conta.Event.TransactionCreated

  alias Conta.Projector.Ledger.Account
  alias Conta.Projector.Ledger.Balance
  alias Conta.Projector.Ledger.Entry

  alias Conta.Repo

  project(%AccountSet{} = account, _metadata, fn multi ->
    parent_id =
      case Enum.split(account.name, -1) do
        {[], _} ->
          nil

        {parent_name, _} ->
          Conta.Repo.get_by!(Account, name: parent_name, ledger: account.ledger).id
      end

    changeset =
      Account.changeset(%{
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

  defp account_names(account_name) do
    Enum.reduce((1..(length(account_name) - 1)//1), [account_name], fn idx, acc ->
      {parent, _} = Enum.split(account_name, -idx)
      [parent | acc]
    end)
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
