defmodule Conta.Projector.Stats.Income do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stats_income" do
    field(:account_name, {:array, :string})
    field(:year, :integer)
    field(:month, :integer)
    field(:currency, Money.Ecto.Currency.Type, default: :EUR)
    field(:balance, Money.Ecto.Amount.Type, default: Money.new(0))

    timestamps(type: :utc_datetime_usec)
  end
end
