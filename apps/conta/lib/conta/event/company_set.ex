defmodule Conta.Event.CompanySet do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :nif, :string
    field :name, :string
    field :address, :string
    field :postcode, :string
    field :city, :string
    field :state, :string
    field :country, :string
    field :details, :string
  end

  @required_fields ~w[nif name address postcode city country]a
  @optional_fields ~w[state details]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> traverse_errors()
  end
end
