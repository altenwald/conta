defmodule Conta.Event.InvoiceCreated.PaymentMethod do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :name, :string
    field :method, :string
    field :details, :string
  end

  @required_fields ~w[name method]a
  @optional_fields ~w[details]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
