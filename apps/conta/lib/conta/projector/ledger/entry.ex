defmodule Conta.Projector.Ledger.Entry do
  use TypedEctoSchema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  typed_schema "ledger_entries" do
    field(:on_date, :date)
    field(:description, :string)
    field(:credit, Money.Ecto.Amount.Type, default: 0)
    field(:debit, Money.Ecto.Amount.Type, default: 0)
    field(:balance, Money.Ecto.Amount.Type, default: 0)
    field(:transaction_id, :binary_id)
    field(:account_name, {:array, :string})
    field(:breakdown, :boolean, default: false)
    field(:related_account_name, {:array, :string})
    field(:change_currency, Money.Ecto.Currency.Type)
    field(:change_credit, Money.Ecto.Amount.Type)
    field(:change_debit, Money.Ecto.Amount.Type)
    timestamps(type: :utc_datetime_usec)
  end
end
