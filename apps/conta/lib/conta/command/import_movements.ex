defmodule Conta.Command.ImportMovements do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  typed_embedded_schema do
    field :reconciliation, :string, default: "default"

    embeds_many :movements, Movement, primary_key: false do
      field :on_date, :date
      field :description, :string
      field :amount, :integer
      field :currency, Money.Ecto.Currency.Type
      field :asset_account_name, {:array, :string}
      field :source, :string
    end
  end

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, [:reconciliation])
    |> cast_embed(:movements, with: &changeset_movement/2, required: true)
  end

  @required_fields ~w[on_date description amount currency asset_account_name]a
  @optional_fields ~w[source]a

  @doc false
  def changeset_movement(model, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  def to_command(changeset) do
    apply_changes(changeset)
  end
end
