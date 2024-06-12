defmodule Conta.Projector.Book.Expense do
  use TypedEctoSchema
  import Ecto.Changeset
  alias Conta.Domain.Expense, as: DomainExpense

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @currencies Enum.map(Map.keys(Money.Currency.all()), &{&1, to_string(&1)})

  typed_schema "book_expenses" do
    field :invoice_number, :string
    field :invoice_date, :date
    field :due_date, :date
    field :category, Ecto.Enum, values: DomainExpense.categories()
    field :subtotal_price, :integer
    field :tax_price, :integer
    field :total_price, :integer
    field :comments, :string
    field :currency, Ecto.Enum, values: @currencies, default: :EUR

    embeds_one :provider, Provider, on_replace: :delete do
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
      # methods are cash, bank (i.e. wire transfer) and
      # gateway (i.e. paypal or stripe)
      @methods ~w[cash bank gateway deposit]a

      field :slug, :string
      field :method, Ecto.Enum, values: @methods
      field :details, :string, default: ""
      field :name, :string
      field :holder, :string
    end

    embeds_many :attachments, Attachment, on_replace: :delete do
      field :name, :string
      field :file, :binary
      field :mimetype, :string
      field :size, :integer
      timestamps()
    end

    field :num_attachments, :integer, virtual: true

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w[invoice_number invoice_date category subtotal_price tax_price total_price currency]a
  @optional_fields ~w[due_date comments]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> cast_embed(:payment_method, with: &changeset_payment_method/2)
    |> cast_embed(:provider, with: &changeset_provider/2)
    |> cast_embed(:company, with: &changeset_company/2)
    |> cast_embed(:attachments, with: &changeset_attachment/2)
  end

  @doc false
  def changeset_payment_method(model, params) do
    model
    |> cast(params, ~w[slug name method details holder]a)
    |> validate_required(~w[slug name method]a)
  end

  @required_fields ~w[name nif country]a
  @optional_fields ~w[intracommunity address postcode city state]a

  @doc false
  def changeset_provider(model \\ %__MODULE__.Provider{}, params) do
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

  @required_fields ~w[name file mimetype size]a
  @optional_fields ~w[inserted_at updated_at]a

  @doc false
  def changeset_attachment(model, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
