defmodule Conta.Command.UpdateMovement do
  use TypedEctoSchema

  @primary_key false

  typed_embedded_schema do
    field :id, :binary_id
    field :changes, :map
    field :reconciliation, :string, default: "default"
  end
end
