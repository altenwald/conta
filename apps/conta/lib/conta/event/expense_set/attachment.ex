defmodule Conta.Event.ExpenseSet.Attachment do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :name, :string
    field :file, :binary
    field :mimetype, :string
    field :size, :integer
    timestamps()
  end

  @required_fields ~w[name file mimetype size]a
  @optional_fields ~w[inserted_at updated_at]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
