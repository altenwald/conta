defmodule Conta.Aggregate.Ledger.Account do
  use TypedEctoSchema
  import Ecto.Changeset
  import Conta.EctoHelpers
  alias Conta.MoneyHelpers

  @account_types ~w[assets liabilities equity revenue expenses]a

  @type balances() :: %{required(atom()) => integer()}

  @primary_key false

  typed_embedded_schema do
    field :id, :binary_id, primary_key: true
    field :name, {:array, :string}
    field :type, Ecto.Enum, values: @account_types
    field(:currency, Money.Currency.Ecto.Type) :: MoneyHelpers.currency()
    field :notes, :string
    field(:balances, :map, default: %{}) :: balances()
  end

  @required_fields ~w[name type currency]a
  @optional_fields ~w[id notes balances]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> get_result()
  end
end
