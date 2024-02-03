defmodule Conta.Projector.Book.Template do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  typed_schema "book_templates" do
    field :nif, :string
    field :name, :string
    field :css, :string, default: ""
    field :logo, :binary
    field :logo_mime_type, :string

    timestamps()
  end

  @required_fields ~w[name]a
  @optional_fields ~w[css logo logo_mime_type]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:name)
  end
end
