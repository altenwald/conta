defmodule Conta.Command.AccountTransaction do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  typed_embedded_schema do
    field :ledger, :string, default: "default"
    field :on_date, :date
    embeds_many :entries, Entry do
      @typep currency() :: atom()

      field :description, :string
      field :account_name, {:array, :string}
      field :credit, Money.Ecto.Amount.Type, default: 0
      field :debit, Money.Ecto.Amount.Type, default: 0
      field(:change_currency, Money.Ecto.Currency.Type, default: :EUR) :: currency()
      field :change_credit, Money.Ecto.Amount.Type, default: 0
      field :change_debit, Money.Ecto.Amount.Type, default: 0
      field :change_price, :decimal, default: 1.0
    end
  end

  @required_fields ~w[on_date]a
  @optional_fields ~w[ledger]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> cast_embed(:entries, with: &changeset_entries/2)
    |> validate_required(@required_fields)
  end

  @required_fields ~w[description account_name]a
  @optional_fields ~w[credit debit change_currency change_credit change_debit change_price]a

  @doc false
  def changeset_entries(model, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
