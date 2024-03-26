defmodule Conta.Event.ShortcutSet do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :name, :string
    field :ledger, :string
    field :description, :string
    embeds_many :params, Param, [primary_key: false, on_replace: :delete] do
      field :name, :string
      field :type, Ecto.Enum, values: ~w[string date integer money currency options account_name]a
      field :options, {:array, :string}
    end
    field :code, :string
    field :language, Ecto.Enum, values: ~w[lua php]a, default: :lua
  end

  @required_fields ~w[name code ledger]a
  @optional_fields ~w[language description]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> cast_embed(:params, with: &changeset_params/2)
    |> validate_required(@required_fields)
    |> traverse_errors()
  end

  @required_fields ~w[name type]a
  @optional_fields ~w[options]a

  @doc false
  def changeset_params(model, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Jason.Encoder, for: Conta.Event.ShortcutSet.Param do
  def encode(param, _opts) do
    Jason.encode!(Map.from_struct(param))
  end
end
