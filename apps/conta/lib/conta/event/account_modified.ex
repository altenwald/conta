defmodule Conta.Event.AccountModified do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @typep currency() :: atom()

  @derive Jason.Encoder
  typed_embedded_schema do
    field :id, :binary_id
    field :type, Ecto.Enum, values: ~w[assets liabilities equity revenue expenses]a
    field(:currency, Money.Ecto.Currency.Type, default: :EUR) :: currency()
    field :notes, :string
  end

  @required_fields ~w[id type currency]a
  @optional_fields ~w[notes]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> traverse_errors()
  end

  def changed_anything?(model, params) do
    changeset = cast(model, params, @required_fields ++ @optional_fields)
    Enum.any?(
      @required_fields ++ @optional_fields,
      &changed?(changeset, &1)
    )
  end
end
