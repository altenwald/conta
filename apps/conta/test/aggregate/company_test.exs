defmodule Conta.Aggregate.CompanyTest do
  use ExUnit.Case

  describe "company" do
    test "create successfully" do
      command = %Conta.Command.SetCompany{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES"
      }

      company = %Conta.Aggregate.Company{}

      event = Conta.Aggregate.Company.execute(company, command)

      assert %Conta.Event.CompanySet{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES"
      } == event

      company = Conta.Aggregate.Company.apply(company, event)

      assert %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES"
      } == company
    end

    test "update successfully" do
      command = %Conta.Command.SetCompany{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES"
      }

      company = %Conta.Aggregate.Company{
        nif: "B111222333",
        name: "Another Company",
        address: "My old address",
        postcode: "08000",
        city: "Barcelona",
        state: "Catalonia",
        country: "ES",
        invoice_numbers: %{2024 => 100},
        template_names: MapSet.new(["default", "another"])
      }

      event = Conta.Aggregate.Company.execute(company, command)

      assert %Conta.Event.CompanySet{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES"
      } == event

      assert %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES",
        invoice_numbers: %{2024 => 100},
        template_names: MapSet.new(["default", "another"])
      } == Conta.Aggregate.Company.apply(company, event)
    end

    test "missing data in creation" do
      command = %Conta.Command.SetCompany{
        nif: "A55666777",
        name: "Great Company SA",
        country: "ES"
      }

      company = %Conta.Aggregate.Company{}

      assert {:error, %{
        state: ["can't be blank"],
        address: ["can't be blank"],
        city: ["can't be blank"],
        postcode: ["can't be blank"]
      }} == Conta.Aggregate.Company.execute(company, command)
    end
  end

  describe "template" do
    test "adding template successfully" do
      company = %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES"
      }

      command = %Conta.Command.SetTemplate{
        nif: "A55666777",
        name: "startup",
        css: "body { color: #333; }"
      }

      event = Conta.Aggregate.Company.execute(company, command)

      assert %Conta.Event.TemplateSet{
        nif: "A55666777",
        name: "startup",
        css: "body { color: #333; }"
      } == event

      assert %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES",
        template_names: MapSet.new(["default", "startup"])
      } == Conta.Aggregate.Company.apply(company, event)
    end
  end

  describe "invoice" do
    test "create successfully" do
      company = %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES"
      }

      command = %Conta.Command.CreateInvoice{
        nif: "A55666777",
        invoice_number: 1,
        invoice_date: Date.new!(2023, 12, 20),
        type: :service,
        subtotal_price: 100_00,
        tax_price: 21_00,
        total_price: 121_00,
        destination_country: "ES",
        payment_method: %Conta.Command.CreateInvoice.PaymentMethod{
          method: :gateway,
          details: "myaccount@paypal.com"
        },
        client: %Conta.Command.CreateInvoice.Client{
          name: "My client",
          nif: "B123456789",
          address: "My client's address",
          postcode: "14000",
          city: "Cordoba",
          state: "Cordoba",
          country: "ES"
        },
        details: [
          %Conta.Command.CreateInvoice.Detail{
            description: "Consultancy",
            tax: 21,
            base_price: 100_00,
            tax_price: 21_00,
            total_price: 121_00
          }
        ]
      }

      event = Conta.Aggregate.Company.execute(company, command)

      assert %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES",
        invoice_numbers: %{2023 => 1},
        template_names: MapSet.new(["default"])
      } == Conta.Aggregate.Company.apply(company, event)
    end
  end
end
