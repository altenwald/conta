defmodule Conta.Command.RemoveExpense do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  typed_embedded_schema do
    field :nif, :string
    field :invoice_number, :string
    field :invoice_date, :date
  end

  @fields ~w[nif invoice_date invoice_number]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @fields)
    |> validate_required(@fields)
  end

  def to_command(changeset) do
    apply_changes(changeset)
  end
end
