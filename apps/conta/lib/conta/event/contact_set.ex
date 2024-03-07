defmodule Conta.Event.ContactSet do
  use TypedEctoSchema
  import Conta.Event
  import Ecto.Changeset

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

  @required_fields ~w[name nif address postcode city country]a
  @optional_fields ~w[intracommunity state]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> traverse_errors()
  end
end
