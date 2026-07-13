defmodule Conta.Projector.Reconciliation.Movement do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder,
           only: ~w[id on_date description amount currency asset_account_name account_name source transacted]a}
  typed_schema "reconciliation_movements" do
    field :on_date, :date
    field :description, :string
    field :amount, :integer
    field :currency, Money.Ecto.Currency.Type
    field :asset_account_name, {:array, :string}
    field :account_name, {:array, :string}
    field :source, :string
    field :transacted, :boolean, default: false
  end

  @required_fields ~w[on_date description amount currency asset_account_name transacted]a
  @optional_fields ~w[account_name source]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
