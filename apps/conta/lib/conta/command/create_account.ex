defmodule Conta.Command.CreateAccount do
  use TypedEctoSchema

  @primary_key false

  @typep currency() :: atom()

  typed_embedded_schema do
    field :name, :string
    field :type, :string
    field(:currency, Money.Ecto.Currency.Type) :: currency()
    field :notes, :string
    field :ledger, :string
  end
end
