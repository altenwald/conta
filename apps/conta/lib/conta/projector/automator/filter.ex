defmodule Conta.Projector.Automator.Filter do
  use TypedEctoSchema
  import Ecto.Changeset
  alias Conta.Projector.Automator.Param

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder, only: ~w[name automator description params code language]a}
  typed_schema "automator_filters" do
    field :name, :string
    field :automator, :string
    field :type, Ecto.Enum, values: ~w[invoice expense entry all]a, default: :all
    field :description, :string
    field :output, Ecto.Enum, values: ~w[json xlsx]a
    embeds_many :params, Param, on_replace: :delete
    field :code, :string
    field :language, Ecto.Enum, values: ~w[lua php]a, default: :lua
  end

  @required_fields ~w[name code automator output]a
  @optional_fields ~w[type language description]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> cast_embed(:params)
    |> validate_required(@required_fields)
  end
end
