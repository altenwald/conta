defmodule Conta.Event.InvoiceCreated.Detail do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :sku, :string
    field :description, :string
    field :tax, :integer
    field :base_price, :integer
    field :units, :integer, default: 1
    field :tax_price, :integer
    field :total_price, :integer
  end

  @required_fields ~w[description tax base_price tax_price total_price]a
  @optional_fields ~w[sku units]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
