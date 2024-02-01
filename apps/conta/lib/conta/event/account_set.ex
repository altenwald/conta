defmodule Conta.Event.AccountSet do
  use TypedEctoSchema
  import Conta.Event
  import Ecto.Changeset

  @primary_key false

  @typep currency() :: atom()

  @derive Jason.Encoder
  typed_embedded_schema do
    field :name, :string
    field :ledger, :string
    field :type, :string
    field(:currency, Money.Ecto.Currency.Type, default: :EUR) :: currency()
    field :notes, :string
  end

  @required_fields ~w[name ledger type]a
  @optional_fields ~w[currency notes]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> traverse_errors()
  end
end
