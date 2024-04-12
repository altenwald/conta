defmodule Conta.Command.CreateInvoice do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  typed_embedded_schema do
    field :nif, :string
    field :client_nif, :string
    field :template, :string
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
    field :payment_method, :string
    embeds_many :details, Detail do
      field :sku, :string
      field :description, :string
      field :tax, :integer
      field :base_price, :decimal
      field :units, :integer, default: 1
      field :tax_price, :decimal
      field :total_price, :decimal
    end
  end

  @required_fields ~w[nif invoice_date currency type subtotal_price tax_price total_price destination_country payment_method]a
  @optional_fields ~w[invoice_number paid_date client_nif template due_date comments]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> cast_embed(:details, required: true, with: &changeset_details/2)
    |> validate_required(@required_fields)
  end

  @required_fields ~w[description tax base_price tax_price total_price]a
  @optional_fields ~w[sku units]a

  @doc false
  def changeset_details(model, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  def to_command(changeset) do
    apply_changes(changeset)
  end
end
