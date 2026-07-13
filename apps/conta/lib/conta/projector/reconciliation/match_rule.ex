defmodule Conta.Projector.Reconciliation.MatchRule do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder, only: ~w[id name conditions match_type account_name position]a}
  typed_schema "reconciliation_match_rules" do
    field :name, :string

    embeds_many :conditions, Condition, on_replace: :delete do
      field :field, Ecto.Enum, values: ~w[description amount on_date]a
      field :comparator, Ecto.Enum, values: ~w[contains equals regex greater_than less_than between]a
      field :value, :string
      field :value_to, :string
    end

    field :match_type, Ecto.Enum, values: ~w[all any]a, default: :all
    field :account_name, {:array, :string}
    field :position, :integer
  end

  @required_fields ~w[name match_type account_name position]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields)
    |> cast_embed(:conditions)
    |> validate_required(@required_fields)
  end
end

defimpl Jason.Encoder, for: Conta.Projector.Reconciliation.MatchRule.Condition do
  def encode(condition, _opts) do
    Jason.encode!(Map.from_struct(condition))
  end
end
