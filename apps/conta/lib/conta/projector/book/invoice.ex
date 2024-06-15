defmodule Conta.Projector.Book.Invoice do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @currencies Enum.map(Map.keys(Money.Currency.all()), &{&1, to_string(&1)})

  @derive {Jason.Encoder, only: ~w[id invoice_number invoice_date template paid_date due_date type subtotal_price tax_price total_price currency comments destination_country client company payment_method details inserted_at updated_at]a}
  typed_schema "book_invoices" do
    field :template, :string, default: "default"
    field :invoice_number, :string
    field :invoice_date, :date
    field :paid_date, :date
    field :due_date, :date
    field :type, Ecto.Enum, values: ~w[product service]a
    field :subtotal_price, :integer
    field :tax_price, :integer
    field :total_price, :integer
    field :currency, Ecto.Enum, values: @currencies, default: :EUR
    field :comments, :string
    field :destination_country, :string

    embeds_one :client, Client, on_replace: :delete do
      @derive {Jason.Encoder, only: ~w[name nif intracommunity address postcode city state country]a}

      field :name, :string
      field :nif, :string
      field :intracommunity, :boolean, default: false
      field :address, :string
      field :postcode, :string
      field :city, :string
      field :state, :string
      field :country, :string
    end

    embeds_one :company, Company, on_replace: :delete do
      @derive {Jason.Encoder, only: ~w[name nif address postcode city state country details]a}

      field :name, :string
      field :nif, :string
      field :address, :string
      field :postcode, :string
      field :city, :string
      field :state, :string
      field :country, :string
      field :details, :string
    end

    embeds_one :payment_method, PaymentMethod, on_replace: :delete do
      @derive {Jason.Encoder, only: ~w[slug name method details holder]a}

      # methods are cash, bank (i.e. wire transfer) and
      # gateway (i.e. paypal or stripe)
      @methods ~w[cash bank gateway]a

      field :slug, :string
      field :method, Ecto.Enum, values: @methods
      field :details, :string, default: ""
      field :name, :string
      field :holder, :string
    end

    embeds_many :details, Detail, on_replace: :delete do
      @derive {Jason.Encoder, ~w[sku description tax base_price units tax_price total_price]a}

      field :sku, :string
      field :description, :string
      field :tax, :integer
      field :base_price, :integer
      field :units, :integer, default: 1
      field :tax_price, :integer
      field :total_price, :integer
    end

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w[invoice_number invoice_date type subtotal_price tax_price total_price destination_country]a
  @optional_fields ~w[paid_date due_date comments template currency]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> cast_embed(:payment_method, with: &changeset_payment_method/2)
    |> cast_embed(:client, with: &changeset_client/2)
    |> cast_embed(:company, with: &changeset_company/2)
    |> cast_embed(:details, with: &changeset_details/2)
  end

  @doc false
  def changeset_payment_method(model, params) do
    model
    |> cast(params, ~w[slug name method details holder]a)
    |> validate_required(~w[name method]a)
  end

  @required_fields ~w[name nif country]a
  @optional_fields ~w[intracommunity address postcode city state]a

  @doc false
  def changeset_client(model, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  @required_fields ~w[name nif country]a
  @optional_fields ~w[address postcode city state details]a

  @doc false
  def changeset_company(model, params) do
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
