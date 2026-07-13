defmodule Conta.Command.RemoveMovement do
  use TypedEctoSchema

  @primary_key false

  typed_embedded_schema do
    field :id, :binary_id
    field :reconciliation, :string, default: "default"
  end
end
