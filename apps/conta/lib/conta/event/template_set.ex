defmodule Conta.Event.TemplateSet do
  use TypedEctoSchema
  import Conta.Event
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :nif, :string
    field :name, :string
    field :css, :string
    field :logo, :binary
    field :logo_mime_type, :string
  end

  @required_fields ~w[nif name css]a
  @optional_fields ~w[logo logo_mime_type]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> traverse_errors()
  end
end
