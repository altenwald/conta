defmodule Conta.Command.CreateInvoice do
  use TypedEctoSchema

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
end
