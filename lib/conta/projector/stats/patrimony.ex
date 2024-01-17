defmodule Conta.Projector.Stats.Patrimony do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stats_patrimony" do
    field :year, :integer
    field :month, :integer
    field :currency, Money.Ecto.Currency.Type, default: :EUR
    field :amount, Money.Ecto.Amount.Type, default: Money.new(0)
    field :balance, Money.Ecto.Amount.Type, default: Money.new(0)

    timestamps(type: :utc_datetime_usec)
  end
end
