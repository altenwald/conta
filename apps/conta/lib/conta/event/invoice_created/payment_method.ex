defmodule Conta.Event.InvoiceCreated.PaymentMethod do
  use TypedEctoSchema
  import Ecto.Changeset

  # methods are cash, bank (i.e. wire transfer) and
  # gateway (i.e. paypal or stripe)
  @methods ~w[cash bank gateway]a

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :method, Ecto.Enum, values: @methods
    field :details, :string
  end

  @required_fields ~w[method details]a
  @optional_fields ~w[]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
