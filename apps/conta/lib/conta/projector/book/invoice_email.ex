defmodule Conta.Projector.Book.InvoiceEmail do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder, only: ~w[id invoice_id to subject body sent_at inserted_at updated_at]a}
  typed_schema "book_invoice_emails" do
    belongs_to :invoice, Conta.Projector.Book.Invoice, foreign_key: :invoice_id
    field :to, :string
    field :subject, :string
    field :body, :string
    field :sent_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w[id invoice_id to subject sent_at]a
  @optional_fields ~w[body]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
