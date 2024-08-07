defmodule Conta.Command.SetContact do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  typed_embedded_schema do
    field :company_nif, :string
    field :name, :string
    field :nif, :string
    field :intracommunity, :boolean, default: false
    field :address, :string
    field :postcode, :string
    field :city, :string
    field :state, :string
    field :country, :string
  end

  @required_fields ~w[company_nif name nif address postcode city country]a
  @optional_fields ~w[intracommunity state]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  def to_command(changeset) do
    apply_changes(changeset)
  end
end
