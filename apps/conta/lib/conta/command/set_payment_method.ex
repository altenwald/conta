defmodule Conta.Command.SetPaymentMethod do
  use TypedEctoSchema

  # methods are cash, bank (i.e. wire transfer),
  # gateway (i.e. paypal or stripe), and
  # deposit (i.e. resellbiz or netim)
  @methods ~w[cash bank gateway deposit]a

  @primary_key false

  typed_embedded_schema do
    field :nif, :string
    field :slug, :string
    field :name, :string
    field :method, Ecto.Enum, values: @methods
    field :details, :string
    field :holder, :string
  end
end
