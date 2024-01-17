defmodule Conta.Projector.Ledger.Entry do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ledger_entries" do
    field(:on_date, :date)
    field(:description, :string)
    field(:credit, Money.Ecto.Amount.Type, default: 0)
    field(:debit, Money.Ecto.Amount.Type, default: 0)
    field(:balance, Money.Ecto.Amount.Type, default: 0)
    field(:transaction_id, :binary_id)
    field(:account_name, {:array, :string})
    field(:breakdown, :boolean, default: false)
    field(:related_account_name, {:array, :string})

    timestamps(type: :utc_datetime_usec)
  end
end
