defmodule Conta.Command.RemoveFilter do
  use TypedEctoSchema

  @primary_key false

  typed_embedded_schema do
    field :name, :string
    field :automator, :string
  end
end
