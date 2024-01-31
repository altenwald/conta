defmodule Conta.Event.AccountCreated do
  use TypedEctoSchema

  @primary_key false

  @typep currency() :: atom()

  @derive Jason.Encoder
  typed_embedded_schema do
    field :name, :string
    field :type, :string
    field(:currency, Money.Ecto.Currency.Type) :: currency()
    field :ledger, :string
    field :notes, :string
  end
end
