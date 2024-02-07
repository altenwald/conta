defmodule Conta.Command.CreateInvoice do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  typed_embedded_schema do
    field :nif, :string
    field :template, :string, default: "default"
    field :invoice_number, :integer
    field :invoice_date, :date
    field :due_date, :date
    field :type, Ecto.Enum, values: ~w[product service]a
    field :subtotal_price, :integer
    field :tax_price, :integer
    field :total_price, :integer
    field :comments, :string
    field :destination_country, :string
    embeds_one :payment_method, PaymentMethod do
      # methods are cash, bank (i.e. wire transfer) and
      # gateway (i.e. paypal or stripe)
      @methods ~w[cash bank gateway]a

      field :method, Ecto.Enum, values: @methods
      field :details, :string
    end
    embeds_one :client, Client do
      field :name, :string
      field :nif, :string
      field :intracommunity, :boolean, default: false
      field :address, :string
      field :postcode, :string
      field :city, :string
      field :state, :string
      field :country, :string
    end
    embeds_many :details, Detail do
      field :sku, :string
      field :description, :string
      field :tax, :integer
      field :base_price, :integer
      field :units, :integer, default: 1
      field :tax_price, :integer
      field :total_price, :integer
    end
  end

  @required_fields ~w[nif invoice_date type subtotal_price tax_price total_price destination_country]a
  @optional_fields ~w[invoice_number template due_date comments]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> cast_embed(:payment_method, with: &changeset_payment/2)
    |> cast_embed(:client, with: &changeset_client/2)
    |> cast_embed(:details, required: true, with: &changeset_details/2)
    |> validate_required(@required_fields)
  end

  @required_fields ~w[method details]a
  @optional_fields ~w[]a

  @doc false
  def changeset_payment(model, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  @required_fields ~w[name nif country]a
  @optional_fields ~w[intracommunity address postcode city state]a

  @doc false
  def changeset_client(model, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
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
end
