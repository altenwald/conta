defmodule Conta.Event.InvoiceSet do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset
  alias Conta.Event.Common.Company
  alias Conta.Event.Common.PaymentMethod
  alias Conta.Event.InvoiceSet.Client
  alias Conta.Event.InvoiceSet.Detail

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :action, Ecto.Enum, values: ~w[insert update]a
    field :template, :string, default: "default"
    field :invoice_number, :integer
    field :invoice_date, :date
    field :paid_date, :date
    field :due_date, :date
    field :type, Ecto.Enum, values: ~w[product service]a
    field :subtotal_price, :decimal
    field :tax_price, :decimal
    field :total_price, :decimal
    field :currency, :string
    field :comments, :string
    field :destination_country, :string
    embeds_one :payment_method, PaymentMethod
    embeds_one :client, Client
    embeds_one :company, Company
    embeds_many :details, Detail
  end

  @required_fields ~w[action invoice_number invoice_date type subtotal_price tax_price total_price currency]a
  @optional_fields ~w[destination_country template paid_date due_date comments]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> cast_embed(:payment_method)
    |> cast_embed(:client)
    |> cast_embed(:company, required: true)
    |> cast_embed(:details, required: true)
    |> validate_required(@required_fields)
    |> get_result()
  end
end
