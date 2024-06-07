defmodule Conta.Event.TransactionRemoved.Entry do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  @typep currency() :: atom()

  @derive Jason.Encoder
  typed_embedded_schema do
    field :account_name, {:array, :string}
    field(:credit, Money.Ecto.Amount.Type, default: Money.new(0)) :: Money.t()
    field(:debit, Money.Ecto.Amount.Type, default: Money.new(0)) :: Money.t()
    field(:balance, Money.Ecto.Amount.Type, default: Money.new(0)) :: Money.t()
    field(:currency, Money.Ecto.Currency.Type, default: :EUR) :: currency()
  end

  @required_fields ~w[account_name balance]a
  @optional_fields ~w[credit debit currency]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
