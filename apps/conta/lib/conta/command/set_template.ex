defmodule Conta.Command.SetTemplate do
  use TypedEctoSchema

  @primary_key false

  typed_embedded_schema do
    field :nif, :string
    field :name, :string
    field :css, :string
    field :logo, :binary
    field :logo_mime_type, :string
  end
end
