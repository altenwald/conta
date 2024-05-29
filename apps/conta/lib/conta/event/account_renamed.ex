defmodule Conta.Event.AccountRenamed do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :id, :binary_id
    field :prev_name, {:array, :string}
    field :new_name, {:array, :string}
    field :ledger, :string
  end

  @required_fields ~w[id prev_name new_name ledger]a
  @optional_fields ~w[]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> get_result()
  end
end
