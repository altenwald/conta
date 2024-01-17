defmodule Conta.Projector.Stats.ProfitsLoses do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stats_profits_loses" do
    field(:year, :integer)
    field(:month, :integer)
    field(:profits, Money.Ecto.Amount.Type, default: Money.new(0))
    field(:loses, Money.Ecto.Amount.Type, default: Money.new(0))
    field(:balance, Money.Ecto.Amount.Type, default: Money.new(0))
    field(:currency, Money.Ecto.Currency.Type, default: :EUR)

    timestamps(type: :utc_datetime_usec)
  end
end
