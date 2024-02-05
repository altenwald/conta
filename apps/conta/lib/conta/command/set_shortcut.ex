defmodule Conta.Command.SetShortcut do
  use TypedEctoSchema

  @primary_key false

  typed_embedded_schema do
    field :name, :string
    field :description, :string
    field :ledger, :string
    embeds_many :params, Param do
      field :name, :string
      field :type, Ecto.Enum, values: ~w[string date integer money currency options account_name]a
      field :options, {:array, :string}
    end
    field :code, :string
    field :language, Ecto.Enum, values: ~w[lua php]a, default: :lua
  end
end
