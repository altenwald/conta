defmodule Conta.Event.TemplateSet do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  typed_embedded_schema do
    field :nif, :string
    field :name, :string
    field :css, :string, default: ""
    field :logo, :binary
    field :logo_mime_type, :string
  end

  @required_fields ~w[nif name]a
  @optional_fields ~w[css logo logo_mime_type]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> traverse_errors()
  end
end

defimpl Jason.Encoder, for: Conta.Event.TemplateSet do
  def encode(value, _opts) do
    Jason.encode!(%{
      nif: value.nif,
      name: value.name,
      css: value.css,
      logo: Base.encode64(value.logo),
      logo_mime_type: value.logo_mime_type
    })
  end
end
