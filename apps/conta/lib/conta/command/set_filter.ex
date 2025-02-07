defmodule Conta.Command.SetFilter do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  typed_embedded_schema do
    field :name, :string
    field :type, Ecto.Enum, values: ~w[invoice expense entry all]a, default: :all
    field :description, :string
    field :automator, :string
    field :output, Ecto.Enum, values: ~w[json xlsx]a

    embeds_many :params, Param do
      field :name, :string
      field :type, Ecto.Enum, values: ~w[string date integer money currency options account_name table]a
      field :options, {:array, :string}
    end

    field :code, :string
    field :language, Ecto.Enum, values: ~w[lua php]a, default: :lua
  end

  @required_fields ~w[name automator code output]a
  @optional_fields ~w[type description language]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> cast_embed(:params, with: &changeset_params/2)
    |> validate_required(@required_fields)
  end

  @required_fields ~w[name type]a
  @optional_fields ~w[options]a

  def changeset_params(model, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  def to_command(changeset) do
    apply_changes(changeset)
  end
end
