defmodule Conta.BookFixtures do
  use ExMachina.Ecto, repo: Conta.Repo

  def invoice_detail_factory do
    %Conta.Projector.Book.Invoice.Detail{
      id: Ecto.UUID.generate(),
      sku: nil,
      description: "Consultancy",
      tax: 21,
      base_price: 100_00,
      units: 1,
      tax_price: 21_00,
      total_price: 12_100
    }
  end

  def invoice_company_factory do
    %Conta.Projector.Book.Invoice.Company{
      id: Ecto.UUID.generate(),
      name: "Great Company SA",
      nif: "A55666777",
      address: "My Full Address",
      postcode: "28000",
      city: "Madrid",
      state: "Madrid",
      country: "ES"
    }
  end

  def invoice_payment_method_factory do
    %Conta.Projector.Book.Invoice.PaymentMethod{
      id: Ecto.UUID.generate(),
      method: :gateway,
      details: "myaccount@paypal.com"
    }
  end

  def payment_method_factory do
    %Conta.Projector.Book.PaymentMethod{
      id: Ecto.UUID.generate(),
      nif: "A55666777",
      name: "Paypal Wallet",
      slug: "paypal",
      method: :gateway,
      details: "",
      holder: nil
    }
  end

  def invoice_factory do
    %Conta.Projector.Book.Invoice{
      client: nil,
      comments: nil,
      company: invoice_company_factory(),
      destination_country: "ES",
      details: [invoice_detail_factory()],
      due_date: nil,
      id: Ecto.UUID.generate(),
      invoice_date: ~D[2023-12-30],
      invoice_number: "2023-00001",
      payment_method: invoice_payment_method_factory(),
      subtotal_price: 100_00,
      tax_price: 21_00,
      template: "default",
      total_price: 121_00,
      type: :service,
      inserted_at: NaiveDateTime.utc_now(),
      updated_at: NaiveDateTime.utc_now()
    }
  end
end
