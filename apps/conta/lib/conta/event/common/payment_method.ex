defmodule Conta.Event.Common.PaymentMethod do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :slug, :string
    field :name, :string
    field :method, :string
    field :details, :string
    field :holder, :string
  end

  @required_fields ~w[name method]a
  @optional_fields ~w[slug details holder]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
