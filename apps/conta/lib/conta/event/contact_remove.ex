defmodule Conta.Event.ContactRemove do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :company_nif, :string
    field :nif, :string
  end

  @fields ~w[company_nif nif]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @fields)
    |> validate_required(@fields)
    |> traverse_errors()
  end
end
