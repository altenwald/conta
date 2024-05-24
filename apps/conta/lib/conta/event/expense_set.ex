defmodule Conta.Event.ExpenseSet do
  use TypedEctoSchema

  import Conta.EctoHelpers
  import Ecto.Changeset

  alias Conta.Event.Common.Company
  alias Conta.Event.Common.PaymentMethod
  alias Conta.Event.ExpenseSet.Attachment
  alias Conta.Event.ExpenseSet.Provider

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :action, Ecto.Enum, values: ~w[insert update]a
    field :invoice_number, :string
    field :invoice_date, :date
    field :due_date, :date
    field :category, :string
    field :subtotal_price, :decimal
    field :tax_price, :decimal
    field :total_price, :decimal
    field :comments, :string
    field :currency, :string
    embeds_one :company, Company
    embeds_one :payment_method, PaymentMethod
    embeds_one :provider, Provider
    embeds_many :attachments, Attachment
  end

  @required_fields ~w[action invoice_number invoice_date category subtotal_price tax_price total_price currency]a
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
