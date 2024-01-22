defmodule Conta.Projector.Ledger do
  use Commanded.Projections.Ecto,
    application: Conta.Commanded.Application,
    repo: Conta.Repo,
    name: __MODULE__

  import Ecto.Query, only: [from: 2]

  alias Conta.Event.AccountCreated
  alias Conta.Event.TransactionCreated

  alias Conta.Projector.Ledger.Account
  alias Conta.Projector.Ledger.Entry

  project(%AccountCreated{} = account, _metadata, fn multi ->
    parent_id =
      case Enum.split(account.name, -1) do
        {[], _} ->
          nil

        {parent_name, _} ->
          Conta.Repo.get_by!(Account, name: parent_name, ledger: account.ledger).id
      end

    account =
      Account.changeset(%{
        notes: account.notes,
        parent_id: parent_id,
        name: account.name,
        type: account.type,
        ledger: account.ledger,
        balances: %{account.currency => 0},
        currency: account.currency
      })

    Ecto.Multi.insert(multi, :create_account, account)
  end)

  project(%TransactionCreated{} = transaction, _metadata, fn multi ->
    entries_len = length(transaction.entries)

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

      account_name = entry.account_name

      base_query =
        from(
          a in Account,
          where: a.name == ^account_name,
          update: [
            set: [
              balances:
                fragment(
                  "COALESCE(?, '{}')::jsonb || ('{\"' || ? || '\":' || (COALESCE( ?::jsonb -> ?, '0' )::integer + (CASE WHEN ? IN ('assets', 'expenses') THEN 1 ELSE -1 END * (?::integer - ?::integer)) )::text || '}')::jsonb",
                  a.balances,
                  ^trans_entry.currency,
                  a.balances,
                  ^trans_entry.currency,
                  a.type,
                  ^entry.debit,
                  ^entry.credit
                )
            ]
          ]
        )

      query =
        Enum.reduce(1..(length(account_name) - 1)//1, base_query, fn idx, acc ->
          {parent, _} = Enum.split(account_name, -idx)
          from(a in acc, or_where: a.name == ^parent)
        end)

      multi
      |> Ecto.Multi.insert({:entry, idx}, entry)
      |> Ecto.Multi.update_all({:account, idx}, query, [])
    end)
  end)

  defp to_date(date) when is_struct(date, Date), do: date

  defp to_date(date) when is_binary(date) do
    Date.from_iso8601!(date)
  end
end
