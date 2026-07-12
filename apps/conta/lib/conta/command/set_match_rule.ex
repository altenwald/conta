defmodule Conta.Command.SetMatchRule do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  @description_comparators ~w[contains equals regex]a
  @amount_comparators ~w[equals greater_than less_than]a
  @on_date_comparators ~w[equals between]a

  typed_embedded_schema do
    field :id, :binary_id
    field :reconciliation, :string, default: "default"
    field :name, :string

    embeds_many :conditions, Condition do
      field :field, Ecto.Enum, values: ~w[description amount on_date]a
      field :comparator, Ecto.Enum, values: ~w[contains equals regex greater_than less_than between]a
      field :value, :string
      field :value_to, :string
    end

    field :match_type, Ecto.Enum, values: ~w[all any]a, default: :all
    field :account_name, {:array, :string}
  end

  @required_fields ~w[name match_type account_name]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields)
    |> cast_embed(:conditions, with: &changeset_condition/2, required: true)
    |> validate_required(@required_fields)
    |> validate_length(:conditions, min: 1)
  end

  @required_fields ~w[field comparator value]a
  @optional_fields ~w[value_to]a

  @doc false
  def changeset_condition(model, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_comparator()
  end

  defp validate_comparator(changeset) do
    field = get_field(changeset, :field)
    comparator = get_field(changeset, :comparator)

    valid_comparators =
      case field do
        :description -> @description_comparators
        :amount -> @amount_comparators
        :on_date -> @on_date_comparators
        _ -> []
      end

    if comparator in valid_comparators do
      changeset
    else
      add_error(changeset, :comparator, "is not valid for field #{field}")
    end
  end

  def to_command(changeset) do
    apply_changes(changeset)
  end
end
