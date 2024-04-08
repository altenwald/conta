defmodule Conta.Event.ExpenseCreated do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset
  alias Conta.Event.Common.Company
  alias Conta.Event.Common.PaymentMethod
  alias Conta.Event.ExpenseCreated.Provider
  alias Conta.Event.ExpenseCreated.Attachment

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :invoice_number, :integer
    field :invoice_date, :date
    field :due_date, :date
    field :category, :string
    field :subtotal_price, :decimal
    field :tax_price, :decimal
    field :total_price, :decimal
    field :comments, :string
    field :currency, :string
    embeds_one :payment_method, PaymentMethod
    embeds_one :client, Client
    embeds_one :company, Company
    embeds_many :details, Detail
  end

  @required_fields ~w[invoice_number invoice_date category subtotal_price tax_price total_price currency]a
  @optional_fields ~w[due_date comments]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> cast_embed(:payment_method)
    |> cast_embed(:provider)
    |> cast_embed(:company, required: true)
    |> cast_embed(:attachments)
    |> validate_required(@required_fields)
    |> traverse_errors()
  end
end
