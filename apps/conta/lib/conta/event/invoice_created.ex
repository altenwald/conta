defmodule Conta.Event.InvoiceCreated do
  use TypedEctoSchema
  import Conta.Event
  import Ecto.Changeset
  alias Conta.Event.InvoiceCreated.Client
  alias Conta.Event.InvoiceCreated.Company
  alias Conta.Event.InvoiceCreated.Detail
  alias Conta.Event.InvoiceCreated.PaymentMethod

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :template, :string, default: "default"
    field :invoice_number, :string
    field :invoice_date, :date
    field :due_date, :date
    field :type, Ecto.Enum, values: ~w[product service]a
    field :subtotal_price, :integer
    field :tax_price, :integer
    field :total_price, :integer
    field :comments, :string
    field :destination_country, :string
    embeds_one :payment_method, PaymentMethod
    embeds_one :client, Client
    embeds_one :company, Company
    embeds_many :details, Detail
  end

  @required_fields ~w[invoice_number invoice_date type subtotal_price tax_price total_price destination_country]a
  @optional_fields ~w[template due_date comments]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> cast_embed(:payment_method)
    |> cast_embed(:client)
    |> cast_embed(:company, required: true)
    |> cast_embed(:details, required: true)
    |> validate_required(@required_fields)
    |> traverse_errors()
  end
end
