defmodule Conta.Command.CreateExpense do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  @categories ~w[
    computers
    bank_fees
    gasoline
    shipping_costs
    representation_expenses
    accounting_fees
    printing_and_stationery
    motor_vehicle_tax
    professional_literature
    motor_vehicle_maintenance
    office_supplies
    other_vehicle_costs
    other_general_costs
    advertising
    vehicle_insurances
    general_insurances
    software
    subscriptions
    phone_and_internet
    transport
    travel_and_accommodation
    web_hosting_or_platforms
  ]a

  typed_embedded_schema do
    field :nif, :string
    field :provider_nif, :string
    field :invoice_number, :integer
    field :invoice_date, :date
    field :paid_date, :date
    field :due_date, :date
    field :category, Ecto.Enum, values: @categories
    field :subtotal_price, :decimal
    field :tax_price, :decimal
    field :total_price, :decimal
    field :currency, Money.Ecto.Currency.Type
    field :comments, :string
    field :payment_method, :string
    embeds_many :attachments, Attachment do
      field :name, :string
      field :file, :binary
      field :mimetype, :string
      field :size, :integer
      timestamps()
    end
  end

  @required_fields ~w[nif provider_nif invoice_number invoice_date category subtotal_price tax_price total_price currency payment_method]a
  @optional_fields ~w[paid_date due_date comments]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> cast_embed(:attachments, required: true, with: &changeset_attachments/2)
    |> validate_required(@required_fields)
  end

  @required_fields ~w[name file mimetype size]a
  @optional_fields ~w[inserted_at updated_at]a

  @doc false
  def changeset_attachments(model, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  def to_command(changeset) do
    apply_changes(changeset)
  end
end
