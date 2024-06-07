defmodule Conta.Event.InvoiceRemoved do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :nif, :string
    field :invoice_number, :integer
    field :invoice_date, :date
  end

  @fields ~w[nif invoice_number invoice_date]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @fields)
    |> validate_required(@fields)
    |> get_result()
  end
end
