defmodule Conta.Projector.Ledger.Balance do
  use TypedEctoSchema
  import Ecto.Changeset
  alias Conta.Projector.Ledger.Account

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  typed_schema "ledger_balances" do
    field(:currency, Money.Ecto.Currency.Type) :: atom()
    field(:amount, Money.Ecto.Amount.Type) :: Money.t()
    belongs_to :account, Account

    timestamps(type: :utc_datetime_usec)
  end

  @optional_fields []
  @required_fields ~w[currency amount account_id]a

  @doc false
  def changeset(model, params) do
    model
    |> cast(params, @optional_fields ++ @required_fields)
    |> validate_required(@required_fields)
  end
end
