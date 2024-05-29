defmodule Conta.Event.AccountCreated do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @typep currency() :: atom()

  @derive Jason.Encoder
  typed_embedded_schema do
    field :id, :binary_id
    field :name, {:array, :string}
    field :ledger, :string
    field :type, Ecto.Enum, values: ~w[assets liabilities equity revenue expenses]a
    field(:currency, Money.Ecto.Currency.Type, default: :EUR) :: currency()
    field :notes, :string
  end

  @required_fields ~w[id name ledger type]a
  @optional_fields ~w[currency notes]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> get_result()
  end
end
