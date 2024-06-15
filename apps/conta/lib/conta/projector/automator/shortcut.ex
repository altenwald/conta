defmodule Conta.Projector.Automator.Shortcut do
  use TypedEctoSchema
  import Ecto.Changeset
  alias Conta.Projector.Automator.ShortcutParam

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  typed_schema "automator_shortcuts" do
    field :name, :string
    field :automator, :string
    field :description, :string
    embeds_many :params, ShortcutParam, on_replace: :delete
    field :code, :string
    field :language, Ecto.Enum, values: ~w[lua php]a, default: :lua
  end

  @required_fields ~w[name code automator]a
  @optional_fields ~w[language description]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> cast_embed(:params)
    |> validate_required(@required_fields)
  end
end
