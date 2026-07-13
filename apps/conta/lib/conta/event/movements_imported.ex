defmodule Conta.Event.MovementsImported do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    embeds_many :movements, Movement, primary_key: false, on_replace: :delete do
      field :id, :binary_id
      field :on_date, :date
      field :description, :string
      field :amount, :integer
      field :currency, Money.Ecto.Currency.Type
      field :asset_account_name, {:array, :string}
      field :account_name, {:array, :string}
      field :source, :string
      field :transacted, :boolean, default: false
    end
  end

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, [])
    |> cast_embed(:movements, with: &changeset_movement/2)
    |> get_result()
  end

  @required_fields ~w[id on_date description amount currency asset_account_name transacted]a
  @optional_fields ~w[account_name source]a

  @doc false
  def changeset_movement(model, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Jason.Encoder, for: Conta.Event.MovementsImported.Movement do
  def encode(movement, _opts) do
    Jason.encode!(Map.from_struct(movement))
  end
end
