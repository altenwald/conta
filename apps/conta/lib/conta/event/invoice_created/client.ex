defmodule Conta.Event.InvoiceCreated.Client do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :name, :string
    field :nif, :string
    field :intracommunity, :boolean, default: false
    field :address, :string
    field :postcode, :string
    field :city, :string
    field :state, :string
    field :country, :string
  end

  @required_fields ~w[name nif country]a
  @optional_fields ~w[intracommunity address postcode city state]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
