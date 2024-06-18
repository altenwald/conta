defmodule Conta.Command.RemoveAccount do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  typed_embedded_schema do
    field :ledger, :string
    field :name, {:array, :string}
  end

  @fields [:ledger, :name]

  @doc false
  def changeset(model, params) do
    model
    |> cast(params, @fields)
    |> validate_required(@fields)
  end
end
