defmodule Conta.Event.TransactionCreated.Entry do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  @typep currency() :: atom()

  @derive Jason.Encoder
  typed_embedded_schema do
    field :description, :string
    field :account_name, {:array, :string}
    field(:credit, Money.Ecto.Amount.Type, default: Money.new(0)) :: Money.t()
    field(:debit, Money.Ecto.Amount.Type, default: Money.new(0)) :: Money.t()
    field(:balance, Money.Ecto.Amount.Type, default: Money.new(0)) :: Money.t()
    field(:change_currency, Money.Ecto.Currency.Type, default: :EUR) :: currency()
    field(:change_credit, Money.Ecto.Amount.Type, default: Money.new(0)) :: Money.t()
    field(:change_debit, Money.Ecto.Amount.Type, default: Money.new(0)) :: Money.t()
  end

  @required_fields ~w[description account_name balance]a
  @optional_fields ~w[credit debit change_currency change_credit change_debit]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
