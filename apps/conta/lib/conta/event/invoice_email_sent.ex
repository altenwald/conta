defmodule Conta.Event.InvoiceEmailSent do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :id, :binary_id
    field :invoice_id, :binary_id
    field :company_nif, :string
    field :to, :string
    field :subject, :string
    field :body, :string
    field :sent_at, :utc_datetime_usec
  end

  @required_fields ~w[id invoice_id company_nif to subject sent_at]a
  @optional_fields ~w[body]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> get_result()
  end
end
