defmodule Conta.Event.MovementUpdated do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :id, :binary_id
    field :on_date, :date
    field :description, :string
    field :amount, :integer
    field :currency, Money.Ecto.Currency.Type
    field :account_name, {:array, :string}
  end

  @fields ~w[id on_date description amount currency account_name]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @fields)
    |> validate_required([:id])
    |> get_result()
  end
end
