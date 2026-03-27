defmodule Conta.Projector.BookTest do
  use Conta.DataCase
  import Conta.BookFixtures
  alias Conta.Projector.Book

  setup do
    version =
      if pv = Repo.get(Book.ProjectionVersion, "Conta.Projector.Book") do
        pv.last_seen_version + 1
      else
        1
      end

    on_exit(fn ->
      Repo.delete_all(Book.Invoice)
      Repo.delete_all(Book.ProjectionVersion)
    end)

    %{
      handler_name: "Conta.Projector.Book",
      event_number: version
    }
  end

  describe "payment_method" do
    test "create successfully", metadata do
      event =
        %Conta.Event.PaymentMethodSet{
          nif: "A55666777",
          slug: "stripe",
          name: "Stripe Payments",
          method: "gateway",
          details: nil
        }

      assert :ok = Book.handle(event, metadata)

      assert %Book.PaymentMethod{
               id: _,
               method: :gateway,
               name: "Stripe Payments",
               nif: "A55666777",
               slug: "stripe"
             } = Repo.get_by!(Book.PaymentMethod, nif: "A55666777", slug: "stripe")
    end

    test "update successfully", metadata do
      payment_method = insert(:payment_method)
      payment_method_id = payment_method.id

      event =
        %Conta.Event.PaymentMethodSet{
          nif: "A55666777",
          slug: "paypal",
          name: "PayPal Wallet",
          method: "gateway",
          details: "Email business@paypal.com"
        }

      assert %Book.PaymentMethod{
               id: ^payment_method_id,
               method: :gateway,
               name: "Paypal Wallet",
               nif: "A55666777",
               slug: "paypal"
             } = Repo.get!(Book.PaymentMethod, payment_method_id)

      assert :ok = Book.handle(event, metadata)

      assert %Book.PaymentMethod{
               id: ^payment_method_id,
               method: :gateway,
               name: "PayPal Wallet",
               nif: "A55666777",
               slug: "paypal",
               details: "Email business@paypal.com"
             } = Repo.get!(Book.PaymentMethod, payment_method_id)
    end
  end

  describe "invoice" do
    test "create successfully", metadata do
      event =
        %Conta.Event.InvoiceSet{
          action: :insert,
          invoice_number: 1,
          invoice_date: ~D"2023-12-30",
          type: :service,
          subtotal_price: 100_00,
          tax_price: 21_00,
          total_price: 121_00,
          destination_country: "ES",
          payment_method: %Conta.Event.Common.PaymentMethod{
            slug: "paypal",
            name: "PayPal",
            method: :gateway,
            details: "myaccount@paypal.com"
          },
          client: %Conta.Event.InvoiceSet.Client{
            name: "My client",
            nif: "B123456789",
            address: "My client's address",
            postcode: "14000",
            city: "Cordoba",
            state: "Cordoba",
            country: "ES"
          },
          details: [
            %Conta.Event.InvoiceSet.Detail{
              description: "Consultancy",
              tax: 21,
              base_price: 100_00,
              tax_price: 21_00,
              total_price: 121_00
            }
          ],
          company: %Conta.Event.Common.Company{
            nif: "A55666777",
            name: "Great Company SA",
            address: "My Full Address",
            postcode: "28000",
            city: "Madrid",
            state: "Madrid",
            country: "ES"
          },
          template: "default"
        }

      assert :ok = Book.handle(event, metadata)

      assert %Book.Invoice{
               client: %Book.Invoice.Client{
                 name: "My client",
                 nif: "B123456789",
                 intracommunity: false,
                 address: "My client's address",
                 postcode: "14000",
                 city: "Cordoba",
                 state: "Cordoba",
                 country: "ES"
               },
               company: %Book.Invoice.Company{
                 name: "Great Company SA",
                 nif: "A55666777",
                 address: "My Full Address",
                 postcode: "28000",
                 city: "Madrid",
                 state: "Madrid",
                 country: "ES"
               },
               destination_country: "ES",
               details: [
                 %Book.Invoice.Detail{
                   description: "Consultancy",
                   tax: 21,
                   base_price: 100_00,
                   units: 1,
                   tax_price: 21_00,
                   total_price: 12_100
                 }
               ],
               invoice_date: ~D[2023-12-30],
               invoice_number: "2023-00001",
               payment_method: %Book.Invoice.PaymentMethod{
                 method: :gateway,
                 details: "myaccount@paypal.com"
               },
               subtotal_price: 100_00,
               tax_price: 21_00,
               total_price: 121_00,
               type: :service
             } = Repo.get_by!(Book.Invoice, invoice_number: "2023-00001")
    end

    test "update successfully", metadata do
      event =
        %Conta.Event.InvoiceSet{
          action: :update,
          invoice_number: 1,
          invoice_date: ~D"2023-12-30",
          type: :service,
          subtotal_price: 100_00,
          tax_price: 21_00,
          total_price: 121_00,
          destination_country: "ES",
          payment_method: %Conta.Event.Common.PaymentMethod{
            slug: "paypal",
            name: "PayPal",
            method: "gateway",
            details: "myaccount@paypal.com"
          },
          client: %Conta.Event.InvoiceSet.Client{
            name: "My client",
            nif: "B123456789",
            address: "My client's address",
            postcode: "14000",
            city: "Cordoba",
            state: "Cordoba",
            country: "ES"
          },
          details: [
            %Conta.Event.InvoiceSet.Detail{
              description: "Consultancy",
              tax: 21,
              base_price: 200_00,
              tax_price: 42_00,
              total_price: 242_00
            }
          ],
          company: %Conta.Event.Common.Company{
            nif: "A55666777",
            name: "Great Company SA",
            address: "My Full Address",
            postcode: "28000",
            city: "Madrid",
            state: "Madrid",
            country: "ES"
          },
          template: "default"
        }

      _invoice = insert(:invoice, %{invoice_number: "2023-00001", invoice_date: "2023-12-30"})

      assert %Conta.Projector.Book.Invoice{
               client: nil,
               company: %Conta.Projector.Book.Invoice.Company{
                 name: "Great Company SA",
                 nif: "A55666777",
                 address: "My Full Address",
                 postcode: "28000",
                 city: "Madrid",
                 state: "Madrid",
                 country: "ES"
               },
               destination_country: "ES",
               details: [
                 %Conta.Projector.Book.Invoice.Detail{
                   description: "Consultancy",
                   tax: 21,
                   base_price: 100_00,
                   units: 1,
                   tax_price: 21_00,
                   total_price: 12_100
                 }
               ],
               invoice_date: ~D[2023-12-30],
               invoice_number: "2023-00001",
               payment_method: %Conta.Projector.Book.Invoice.PaymentMethod{
                 method: :gateway,
                 details: "myaccount@paypal.com"
               },
               subtotal_price: 100_00,
               tax_price: 21_00,
               total_price: 121_00,
               type: :service
             } = Repo.get_by!(Conta.Projector.Book.Invoice, invoice_number: "2023-00001")

      assert :ok = Book.handle(event, metadata)

      assert %Book.Invoice{
               client: %Book.Invoice.Client{
                 name: "My client",
                 nif: "B123456789",
                 intracommunity: false,
                 address: "My client's address",
                 postcode: "14000",
                 city: "Cordoba",
                 state: "Cordoba",
                 country: "ES"
               },
               company: %Conta.Projector.Book.Invoice.Company{
                 name: "Great Company SA",
                 nif: "A55666777",
                 address: "My Full Address",
                 postcode: "28000",
                 city: "Madrid",
                 state: "Madrid",
                 country: "ES"
               },
               destination_country: "ES",
               details: [
                 %Conta.Projector.Book.Invoice.Detail{
                   description: "Consultancy",
                   tax: 21,
                   base_price: 200_00,
                   units: 1,
                   tax_price: 42_00,
                   total_price: 242_00
                 }
               ],
               invoice_date: ~D[2023-12-30],
               invoice_number: "2023-00001",
               payment_method: %Conta.Projector.Book.Invoice.PaymentMethod{
                 slug: "paypal",
                 name: "PayPal",
                 method: :gateway,
                 details: "myaccount@paypal.com"
               },
               subtotal_price: 100_00,
               tax_price: 21_00,
               total_price: 121_00,
               type: :service
             } = Repo.get_by!(Conta.Projector.Book.Invoice, invoice_number: "2023-00001")
    end
  end

  describe "expense" do
    test "create successfully", metadata do
      event =
        %Conta.Event.ExpenseSet{
          action: :insert,
          invoice_number: "EXP-001",
          invoice_date: ~D"2023-12-30",
          category: "office_supplies",
          subtotal_price: Decimal.new("50.00"),
          tax_price: Decimal.new("10.50"),
          total_price: Decimal.new("60.50"),
          currency: "EUR",
          company: %Conta.Event.Common.Company{
            nif: "A55666777",
            name: "Great Company SA",
            country: "ES"
          },
          provider: %Conta.Event.ExpenseSet.Provider{
            name: "Supermarket",
            nif: "B99888777",
            country: "ES"
          },
          attachments: []
        }

      assert :ok = Book.handle(event, metadata)

      assert %Book.Expense{
               invoice_number: "EXP-001",
               category: :office_supplies,
               subtotal_price: 50_00,
               tax_price: 10_50,
               total_price: 60_50,
               currency: :EUR,
               provider: %Book.Expense.Provider{
                 name: "Supermarket"
               }
             } = Repo.get_by!(Book.Expense, invoice_number: "EXP-001")
    end

    test "update successfully", metadata do
      event1 =
        %Conta.Event.ExpenseSet{
          action: :insert,
          invoice_number: "EXP-002",
          invoice_date: ~D"2023-12-30",
          category: "office_supplies",
          subtotal_price: Decimal.new("50.00"),
          tax_price: Decimal.new("10.50"),
          total_price: Decimal.new("60.50"),
          currency: "EUR",
          company: %Conta.Event.Common.Company{
            nif: "A55666777",
            name: "Great Company SA",
            country: "ES"
          },
          provider: %Conta.Event.ExpenseSet.Provider{
            name: "Supermarket",
            nif: "B99888777",
            country: "ES"
          },
          attachments: []
        }

      assert :ok = Book.handle(event1, metadata)

      event2 = %{event1 | action: :update, subtotal_price: Decimal.new("100.00")}
      metadata2 = %{metadata | event_number: metadata.event_number + 1}
      assert :ok = Book.handle(event2, metadata2)

      assert %Book.Expense{
               subtotal_price: 100_00
             } = Repo.get_by!(Book.Expense, invoice_number: "EXP-002")
    end
  end

  describe "template" do
    test "create successfully", metadata do
      event =
        %Conta.Event.TemplateSet{
          nif: "A55666777",
          name: "default",
          css: "body { color: red; }",
          logo: Base.encode64("dummy-logo-data"),
          logo_mime_type: "image/png"
        }

      assert :ok = Book.handle(event, metadata)

      assert %Book.Template{
               name: "default",
               css: "body { color: red; }",
               logo: "dummy-logo-data",
               logo_mime_type: "image/png"
             } = Repo.get_by!(Book.Template, name: "default")
    end
  end
end
