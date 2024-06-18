defmodule Conta.Event.AccountRemoved do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @derive {Jason.Encoder, only: [:ledger, :name]}
  typed_embedded_schema do
    field :ledger, :string
    field :name, {:array, :string}
  end

  @fields [:ledger, :name]

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @fields)
    |> validate_required(@fields)
    |> get_result()
  end
end
