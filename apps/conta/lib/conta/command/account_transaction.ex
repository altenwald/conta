defmodule Conta.Command.AccountTransaction do
  use TypedEctoSchema
  alias Conta.Command.AccountTransaction.Entry

  @primary_key false

  typed_embedded_schema do
    field :ledger, :string
    field :on_date, :date
    embeds_many :entries, Entry
  end
end
