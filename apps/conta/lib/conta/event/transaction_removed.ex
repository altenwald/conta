defmodule Conta.Event.TransactionRemoved do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset
  alias __MODULE__.Entry

  @primary_key {:id, :binary_id, autogenerate: false}

  @derive Jason.Encoder
  typed_embedded_schema do
    field :ledger, :string, default: "default"
    embeds_many :entries, Entry
  end

  @required_fields ~w[id]a
  @optional_fields ~w[ledger]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) when not is_struct(params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> get_result()
  end
end
