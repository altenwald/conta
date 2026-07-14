defmodule Conta.Event.ImporterSet do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :name, :string
    field :automator, :string
    field :description, :string
    field :code, :string
    field :language, Ecto.Enum, values: ~w[lua php]a, default: :lua
  end

  @required_fields ~w[name code automator]a
  @optional_fields ~w[language description]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> get_result()
  end
end
