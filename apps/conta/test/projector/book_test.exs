defmodule Conta.Projector.BookTest do
  use Conta.DataCase
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
    end)

    %{
      handler_name: "Conta.Projector.Book",
      event_number: version
    }
  end

  describe "invoice" do
    test "create successfully", metadata do
      event =
        %Conta.Event.InvoiceCreated{
          invoice_number: "2023-00001",
          invoice_date: ~D[2023-12-30],
          type: :service,
          subtotal_price: 100_00,
          tax_price: 21_00,
          total_price: 121_00,
          destination_country: "ES",
          payment_method: %Conta.Event.InvoiceCreated.PaymentMethod{
            method: :gateway,
            details: "myaccount@paypal.com"
          },
          client: %Conta.Event.InvoiceCreated.Client{
            name: "My client",
            nif: "B123456789",
            address: "My client's address",
            postcode: "14000",
            city: "Cordoba",
            state: "Cordoba",
            country: "ES"
          },
          details: [
            %Conta.Event.InvoiceCreated.Detail{
              description: "Consultancy",
              tax: 21,
              base_price: 100_00,
              tax_price: 21_00,
              total_price: 121_00
            }
          ],
          company: %Conta.Event.InvoiceCreated.Company{
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

      assert :ok = Conta.Projector.Book.handle(event, metadata)

      assert %Conta.Projector.Book.Invoice{
        client: %Conta.Projector.Book.Invoice.Client{
          id: _,
          name: "My client",
          nif: "B123456789",
          intracommunity: false,
          address: "My client's address",
          postcode: "14000",
          city: "Cordoba", state: "Cordoba", country: "ES"},
        comments: nil,
        company: %Conta.Projector.Book.Invoice.Company{
          id: _,
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
            id: _,
            sku: nil,
            description: "Consultancy",
            tax: 21,
            base_price: 100_00,
            units: 1,
            tax_price: 21_00,
            total_price: 12_100
          }
        ],
        due_date: nil,
        id: _,
        invoice_date: ~D[2023-12-30],
        invoice_number: "2023-00001",
        payment_method: %Conta.Projector.Book.Invoice.PaymentMethod{
          id: _,
          method: :gateway,
          details: "myaccount@paypal.com"
        },
        subtotal_price: 100_00,
        tax_price: 21_00,
        template: "default",
        total_price: 121_00,
        type: :service,
        inserted_at: _,
        updated_at: _
      } = Repo.get_by!(Conta.Projector.Book.Invoice, invoice_number: "2023-00001")
    end
  end
end
