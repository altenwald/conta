defmodule Conta.Event.TransactionCreated do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset
  alias __MODULE__.Entry

  @primary_key {:id, :binary_id, autogenerate: false}

  @derive Jason.Encoder
  typed_embedded_schema do
    field :ledger, :string, default: "default"
    field :on_date, :date
    embeds_many :entries, Entry
  end

  @required_fields ~w[on_date]a
  @optional_fields ~w[id ledger]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) when not is_struct(params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> cast_embed(:entries)
    |> validate_required(@required_fields)
    |> get_result()
  end
end
