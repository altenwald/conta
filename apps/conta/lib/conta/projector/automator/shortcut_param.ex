defmodule Conta.Projector.Automator.ShortcutParam do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  @derive {Jason.Encoder, only: ~w[name type options]a}
  typed_embedded_schema do
    field :name, :string, primary_key: true
    field :type, Ecto.Enum, values: ~w[string date integer money currency options account_name table]a
    field :options, {:array, :string}
  end

  @required_fields ~w[name type]a
  @optional_fields ~w[options]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
