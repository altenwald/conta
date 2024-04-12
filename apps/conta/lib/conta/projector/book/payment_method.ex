defmodule Conta.Projector.Book.PaymentMethod do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @methods ~w[cash bank gateway deposit]a

  typed_schema "book_payment_methods" do
    field :nif, :string
    field :name, :string
    field :slug, :string
    field :method, Ecto.Enum, values: @methods, default: :gateway
    field :details, :string, default: ""
    field :holder, :string
  end

  @required_fields ~w[nif name slug]a
  @optional_fields ~w[method details holder]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
