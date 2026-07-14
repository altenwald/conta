defmodule Conta.Command.SetImporter do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  typed_embedded_schema do
    field :name, :string
    field :description, :string
    field :automator, :string
    field :code, :string
    field :language, Ecto.Enum, values: ~w[lua php]a, default: :lua
  end

  @required_fields ~w[name automator code]a
  @optional_fields ~w[description language]a

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
