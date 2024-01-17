defmodule Conta.Projector.Stats do
  use Commanded.Projections.Ecto,
    application: Conta.Application,
    repo: Conta.Repo,
    name: __MODULE__

  import Ecto.Query, only: [from: 2]

  alias Conta.Event.AccountCreated
  alias Conta.Event.TransactionCreated

  alias Conta.Projector.Stats.Account
  alias Conta.Projector.Stats.Income
  alias Conta.Projector.Stats.Outcome
  alias Conta.Projector.Stats.Patrimony
  alias Conta.Projector.Stats.ProfitsLoses

  alias Conta.Repo

  project(%AccountCreated{} = account, _metadata, fn multi ->
    account =
      Account.changeset(%{
        name: account.name,
        ledger: account.ledger,
        type: account.type
      })

    Ecto.Multi.insert(multi, :create_account, account)
  end)

  project(%TransactionCreated{} = transaction, _metadata, fn multi ->
    accounts =
      transaction.entries
      |> Enum.map(& &1.account_name)
      |> Enum.uniq()
      |> Enum.map(&Repo.get_by!(Account, name: &1))
      |> Enum.map(&{&1.name, &1})
      |> Map.new()

    on_date = Date.from_iso8601!(transaction.on_date)

    transaction.entries
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {entry, idx}, multi ->
      account = accounts[entry.account_name]

      multi
      |> maybe_update_income(account.type, on_date, idx, entry)
      |> maybe_update_outcome(account.type, on_date, idx, entry)
      |> maybe_update_patrimony(account.type, on_date, idx, entry)
      |> maybe_update_pnl(account.type, on_date, idx, entry)
    end)
  end)

  defp maybe_update_income(multi, :revenue, on_date, idx, entry) do
    income =
      %Income{
        account_name: entry.account_name,
        year: on_date.year,
        month: on_date.month,
        currency: entry.currency,
        balance: entry.credit - entry.debit
      }

    update = [inc: [balance: entry.credit - entry.debit]]
    opts = [on_conflict: update, conflict_target: ~w[account_name year month currency]a]
    Ecto.Multi.insert(multi, {:income, idx}, income, opts)
  end

  defp maybe_update_income(multi, _type, _on_date, _idx, _entry), do: multi

  defp maybe_update_outcome(multi, :expenses, on_date, idx, entry) do
    outcome =
      %Outcome{
        account_name: entry.account_name,
        year: on_date.year,
        month: on_date.month,
        currency: entry.currency,
        balance: entry.debit - entry.credit
      }

    update = [inc: [balance: entry.debit - entry.credit]]
    opts = [on_conflict: update, conflict_target: ~w[account_name year month currency]a]
    Ecto.Multi.insert(multi, {:outcome, idx}, outcome, opts)
  end

  defp maybe_update_outcome(multi, _type, _on_date, _idx, _entry), do: multi

  defp maybe_update_patrimony(multi, type, on_date, idx, entry)
       when type in [:liabilities, :assets] do
    opts = [year: on_date.year, month: on_date.month, currency: entry.currency]
    # even when liabilities and assets are increased in a different way, we need to
    # compound the data as (assets - liabilities) so if we keep the amount changing
    # the symbol (same for liabilities and assets) we could get the correct value
    # for the patrimony.
    amount = entry.debit - entry.credit

    if Repo.get_by(Patrimony, opts) do
      query =
        from(
          p in Patrimony,
          where:
            p.year == ^on_date.year and p.month == ^on_date.month and
              p.currency == ^entry.currency
        )

      updates = [inc: [balance: amount, amount: amount]]
      Ecto.Multi.update_all(multi, {:patrimony, idx}, query, updates)
    else
      from(
        p in Patrimony,
        where: p.currency == ^entry.currency,
        order_by: [desc: p.year, desc: p.month],
        limit: 1
      )
      |> Repo.one()
      |> case do
        nil ->
          patrimony =
            %Patrimony{
              year: on_date.year,
              month: on_date.month,
              currency: entry.currency,
              amount: amount,
              balance: amount
            }

          update = [inc: [balance: amount, amount: amount]]
          opts = [on_conflict: update, conflict_target: ~w[year month currency]a]
          Ecto.Multi.insert(multi, {:patrimony, idx}, patrimony, opts)

        patrimony ->
          patrimony =
            %Patrimony{
              year: on_date.year,
              month: on_date.month,
              currency: entry.currency,
              amount: amount,
              balance: patrimony.balance.amount + amount
            }

          update = [inc: [balance: amount, amount: amount]]
          opts = [on_conflict: update, conflict_target: ~w[year month currency]a]
          Ecto.Multi.insert(multi, {:patrimony, idx}, patrimony, opts)
      end
    end
  end

  defp maybe_update_patrimony(multi, _type, _on_date, _idx, _entry), do: multi

  defp maybe_update_pnl(multi, type, on_date, idx, entry) when type in [:revenue, :expenses] do
    profits = if type == :revenue, do: entry.credit - entry.debit, else: 0
    loses = if type == :expenses, do: entry.debit - entry.credit, else: 0
    balance = profits - loses

    profits_loses =
      %ProfitsLoses{
        year: on_date.year,
        month: on_date.month,
        currency: entry.currency,
        profits: profits,
        loses: loses,
        balance: balance
      }

    update = [inc: [profits: profits, loses: loses, balance: balance]]
    opts = [on_conflict: update, conflict_target: ~w[year month currency]a]
    Ecto.Multi.insert(multi, {:profits_loses, idx}, profits_loses, opts)
  end

  defp maybe_update_pnl(multi, _type, _on_date, _idx, _entry), do: multi
end
