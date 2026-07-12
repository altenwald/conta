defmodule Conta.Command.ReorderMatchRules do
  use TypedEctoSchema

  @primary_key false

  typed_embedded_schema do
    field :ids, {:array, :binary_id}
    field :reconciliation, :string, default: "default"
  end
end
