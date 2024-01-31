defmodule Conta.Event.TransactionCreated do
  use TypedEctoSchema
  alias Conta.Event.TransactionCreated.Entry

  @primary_key {:id, :binary_id, autogenerate: false}

  @derive Jason.Encoder
  typed_embedded_schema do
    field :ledger, :string
    field :on_date, :date
    embeds_many :entries, Entry
  end
end
