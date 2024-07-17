defmodule Conta.Projector.Stats do
  use Conta.Projector,
    application: Conta.Commanded.Application,
    repo: Conta.Repo,
    name: __MODULE__,
    consistency: Application.compile_env(:conta, :consistency, :eventual)

  import Conta.MoneyHelpers
  import Ecto.Query, only: [from: 2]

  alias Conta.Event.AccountCreated
  alias Conta.Event.AccountModified
  alias Conta.Event.AccountRemoved
  alias Conta.Event.AccountRenamed
  alias Conta.Event.TransactionCreated
  alias Conta.Event.TransactionRemoved

  alias Conta.Projector.Stats.Account
  alias Conta.Projector.Stats.Income
  alias Conta.Projector.Stats.Outcome
  alias Conta.Projector.Stats.Patrimony
  alias Conta.Projector.Stats.ProfitsLoses

  alias Conta.Repo

  project(%AccountCreated{} = account, _metadata, fn multi ->
    account =
      Account.changeset(%{
        id: account.id,
        name: account.name,
        ledger: account.ledger,
        type: account.type,
        currency: account.currency
      })

    Ecto.Multi.insert(multi, :create_account, account)
  end)

  project(%AccountModified{} = account_modified, _metadata, fn multi ->
    account = Repo.get!(Account, account_modified.id)
    params = Map.from_struct(account_modified)
    changeset = Account.changeset(account, params)
    Ecto.Multi.update(multi, :modify_account, changeset)
  end)

  project(%AccountRenamed{} = account_renamed, _metadata, fn multi ->
    account = Repo.get!(Account, account_renamed.id)
    changeset = Account.changeset(account, %{name: account_renamed.new_name})
    Ecto.Multi.update(multi, :rename_account, changeset)
  end)

  project(%AccountRemoved{} = account_removed, _metadata, fn multi ->
    account = Repo.get_by!(Account, ledger: account_removed.ledger, name: account_removed.name)
    Ecto.Multi.delete(multi, :remove_account, account)
  end)

  project(%TransactionCreated{} = transaction, _metadata, fn multi ->
    accounts =
      transaction.entries
      |> Enum.map(& &1.account_name)
      |> Enum.uniq()
      |> Enum.map(&Repo.get_by!(Account, name: &1))
      |> Map.new(&{&1.name, &1})

    on_date = transaction.on_date

    transaction.entries
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {entry, idx}, multi ->
      account = accounts[entry.account_name]

      multi
      |> maybe_update_income(account.type, account.currency, on_date, idx, entry)
      |> maybe_update_outcome(account.type, account.currency, on_date, idx, entry)
      |> maybe_update_patrimony(account.type, account.currency, on_date, idx, entry)
      |> maybe_update_pnl(account.type, account.currency, on_date, idx, entry)
    end)
  end)

  project(%TransactionRemoved{} = transaction, _metadata, fn multi ->
    accounts =
      transaction.entries
      |> Enum.map(& &1.account_name)
      |> Enum.uniq()
      |> Enum.map(&Repo.get_by!(Account, name: &1))
      |> Map.new(&{&1.name, &1})

    on_date = transaction.on_date

    transaction.entries
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {entry, idx}, multi ->
      account = accounts[entry.account_name]
      inverse_entry = Map.merge(entry, %{credit: entry.debit, debit: entry.credit})

      multi
      |> maybe_update_income(account.type, account.currency, on_date, idx, inverse_entry)
      |> maybe_update_outcome(account.type, account.currency, on_date, idx, inverse_entry)
      |> maybe_update_patrimony(account.type, account.currency, on_date, idx, inverse_entry)
      |> maybe_update_pnl(account.type, account.currency, on_date, idx, inverse_entry)
    end)
  end)

  defp maybe_update_income(multi, :revenue, currency, on_date, idx, entry) do
    income =
      %Income{
        account_name: entry.account_name,
        year: on_date.year,
        month: on_date.month,
        currency: currency,
        balance: Money.subtract(entry.credit, entry.debit)
      }

    update = [
      inc: [balance: Money.subtract(entry.credit, entry.debit)],
      set: [updated_at: NaiveDateTime.utc_now()]
    ]

    opts = [on_conflict: update, conflict_target: ~w[account_name year month currency]a]
    Ecto.Multi.insert(multi, {:income, idx}, income, opts)
  end

  defp maybe_update_income(multi, _type, _currency, _on_date, _idx, _entry), do: multi

  defp maybe_update_outcome(multi, :expenses, currency, on_date, idx, entry) do
    balance = Money.subtract(entry.debit, entry.credit)

    outcome =
      %Outcome{
        account_name: entry.account_name,
        year: on_date.year,
        month: on_date.month,
        currency: currency,
        balance: balance
      }

    update = [inc: [balance: balance], set: [updated_at: NaiveDateTime.utc_now()]]
    opts = [on_conflict: update, conflict_target: ~w[account_name year month currency]a]
    Ecto.Multi.insert(multi, {:outcome, idx}, outcome, opts)
  end

  defp maybe_update_outcome(multi, _type, _currency, _on_date, _idx, _entry), do: multi

  defp maybe_update_patrimony(multi, type, currency, on_date, idx, entry)
       when type in [:liabilities, :assets] do
    # even when liabilities and assets are increased in a different way, we need to
    # compound the data as (assets - liabilities) so if we keep the amount changing
    # the symbol (same for liabilities and assets) we could get the correct value
    # for the patrimony.
    amount = Money.subtract(entry.debit, entry.credit)
    opts = [year: on_date.year, month: on_date.month, currency: currency]

    if Repo.get_by(Patrimony, opts) do
      query =
        from(
          p in Patrimony,
          where:
            p.year == ^on_date.year and p.month == ^on_date.month and
              p.currency == ^currency
        )

      updates = [
        inc: [balance: amount, amount: amount],
        set: [updated_at: NaiveDateTime.utc_now()]
      ]

      Ecto.Multi.update_all(multi, {:patrimony, idx}, query, updates)
    else
      from(
        p in Patrimony,
        where: p.currency == ^currency,
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
              currency: currency,
              amount: amount,
              balance: amount
            }

          update = [
            inc: [balance: amount, amount: amount],
            set: [updated_at: NaiveDateTime.utc_now()]
          ]

          opts = [on_conflict: update, conflict_target: ~w[year month currency]a]
          Ecto.Multi.insert(multi, {:patrimony, idx}, patrimony, opts)

        patrimony ->
          patrimony =
            %Patrimony{
              year: on_date.year,
              month: on_date.month,
              currency: currency,
              amount: amount,
              balance: Money.add(patrimony.balance, amount)
            }

          update = [
            inc: [balance: amount, amount: amount],
            set: [updated_at: NaiveDateTime.utc_now()]
          ]

          opts = [on_conflict: update, conflict_target: ~w[year month currency]a]
          Ecto.Multi.insert(multi, {:patrimony, idx}, patrimony, opts)
      end
    end
  end

  defp maybe_update_patrimony(multi, _type, _currency, _on_date, _idx, _entry), do: multi

  defp maybe_update_pnl(multi, type, currency, on_date, idx, entry)
       when type in [:revenue, :expenses] do
    zero = Money.new(0, currency)
    credit = to_money(entry.credit, currency)
    debit = to_money(entry.debit, currency)
    profits = if type == :revenue, do: Money.subtract(credit, debit), else: zero
    loses = if type == :expenses, do: Money.subtract(debit, credit), else: zero
    balance = Money.subtract(profits, loses)

    profits_loses =
      %ProfitsLoses{
        year: on_date.year,
        month: on_date.month,
        currency: currency,
        profits: profits,
        loses: loses,
        balance: balance
      }

    update = [
      inc: [
        profits: profits.amount,
        loses: loses.amount,
        balance: balance.amount
      ],
      set: [
        updated_at: NaiveDateTime.utc_now()
      ]
    ]

    opts = [on_conflict: update, conflict_target: ~w[year month currency]a]
    Ecto.Multi.insert(multi, {:profits_loses, idx}, profits_loses, opts)
  end

  defp maybe_update_pnl(multi, _type, _currency, _on_date, _idx, _entry), do: multi
end
