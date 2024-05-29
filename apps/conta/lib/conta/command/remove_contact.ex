defmodule Conta.Command.RemoveContact do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

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
    |> get_result()
  end
end
