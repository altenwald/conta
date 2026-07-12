defmodule Conta.Event.MatchRuleSet do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :id, :binary_id
    field :name, :string

    embeds_many :conditions, Condition, primary_key: false, on_replace: :delete do
      field :field, Ecto.Enum, values: ~w[description amount on_date]a
      field :comparator, Ecto.Enum, values: ~w[contains equals regex greater_than less_than between]a
      field :value, :string
      field :value_to, :string
    end

    field :match_type, Ecto.Enum, values: ~w[all any]a, default: :all
    field :account_name, {:array, :string}
  end

  @required_fields ~w[id name match_type account_name]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields)
    |> cast_embed(:conditions, with: &changeset_condition/2)
    |> validate_required(@required_fields)
    |> get_result()
  end

  @required_fields ~w[field comparator value]a
  @optional_fields ~w[value_to]a

  @doc false
  def changeset_condition(model, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Jason.Encoder, for: Conta.Event.MatchRuleSet.Condition do
  def encode(condition, _opts) do
    Jason.encode!(Map.from_struct(condition))
  end
end
