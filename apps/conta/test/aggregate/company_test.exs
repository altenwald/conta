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

      assert {:error,
              %{
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

    test "updating template successfully" do
      company = %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES",
        template_names: MapSet.new(["default", "startup"])
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

  describe "contact" do
    test "adding contact successfully" do
      company = %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES"
      }

      command = %Conta.Command.SetContact{
        company_nif: "A55666777",
        nif: "B123456789",
        name: "Limited Company SL",
        intracommunity: true,
        address: "Full Address Here",
        postcode: "08080",
        city: "Barcelona",
        state: "Catalunya",
        country: "ES"
      }

      event = Conta.Aggregate.Company.execute(company, command)

      assert %Conta.Event.ContactSet{
               company_nif: "A55666777",
               nif: "B123456789",
               name: "Limited Company SL",
               intracommunity: true,
               address: "Full Address Here",
               postcode: "08080",
               city: "Barcelona",
               state: "Catalunya",
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
               contacts: %{
                 "B123456789" => %Conta.Aggregate.Company.Contact{
                   name: "Limited Company SL",
                   nif: "B123456789",
                   intracommunity: true,
                   address: "Full Address Here",
                   postcode: "08080",
                   city: "Barcelona",
                   state: "Catalunya",
                   country: "ES"
                 }
               }
             } == Conta.Aggregate.Company.apply(company, event)
    end

    test "updating contact successfully" do
      company = %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES",
        contacts: %{
          "B123456789" => %Conta.Aggregate.Company.Contact{
            name: "Limited Company SL",
            nif: "B123456789",
            intracommunity: true,
            address: "Full Address Here",
            postcode: "08080",
            city: "Barcelona",
            state: "Catalunya",
            country: "ES"
          }
        }
      }

      command = %Conta.Command.SetContact{
        company_nif: "A55666777",
        nif: "B123456789",
        name: "Anonymous Company SA",
        intracommunity: true,
        address: "Full Address Here",
        postcode: "28080",
        city: "Madrid",
        state: "Madrid",
        country: "ES"
      }

      event = Conta.Aggregate.Company.execute(company, command)

      assert %Conta.Event.ContactSet{
               company_nif: "A55666777",
               nif: "B123456789",
               name: "Anonymous Company SA",
               intracommunity: true,
               address: "Full Address Here",
               postcode: "28080",
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
               contacts: %{
                 "B123456789" => %Conta.Aggregate.Company.Contact{
                   name: "Anonymous Company SA",
                   nif: "B123456789",
                   intracommunity: true,
                   address: "Full Address Here",
                   postcode: "28080",
                   city: "Madrid",
                   state: "Madrid",
                   country: "ES"
                 }
               }
             } == Conta.Aggregate.Company.apply(company, event)
    end

    test "remove contact successfully" do
      company = %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES",
        contacts: %{
          "B123456789" => %Conta.Aggregate.Company.Contact{
            name: "Limited Company SL",
            nif: "B123456789",
            intracommunity: true,
            address: "Full Address Here",
            postcode: "08080",
            city: "Barcelona",
            state: "Catalunya",
            country: "ES"
          }
        }
      }

      command = %Conta.Command.RemoveContact{
        company_nif: "A55666777",
        nif: "B123456789"
      }

      event = Conta.Aggregate.Company.execute(company, command)

      assert %Conta.Event.ContactRemoved{
               company_nif: "A55666777",
               nif: "B123456789"
             } == event

      assert %Conta.Aggregate.Company{
               nif: "A55666777",
               name: "Great Company SA",
               address: "My Full Address",
               postcode: "28000",
               city: "Madrid",
               state: "Madrid",
               country: "ES",
               contacts: %{}
             } == Conta.Aggregate.Company.apply(company, event)
    end
  end

  describe "payment method" do
    test "adding payment method successfully" do
      company = %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES"
      }

      command = %Conta.Command.SetPaymentMethod{
        nif: "A55666777",
        slug: "paypal",
        name: "PayPal",
        method: :gateway,
        details: "Account myaccount@paypal.com"
      }

      event = Conta.Aggregate.Company.execute(company, command)

      assert %Conta.Event.PaymentMethodSet{
               nif: "A55666777",
               slug: "paypal",
               name: "PayPal",
               method: "gateway",
               details: "Account myaccount@paypal.com"
             } == event

      assert %Conta.Aggregate.Company{
               nif: "A55666777",
               name: "Great Company SA",
               address: "My Full Address",
               postcode: "28000",
               city: "Madrid",
               state: "Madrid",
               country: "ES",
               payment_methods: %{
                 "paypal" => %Conta.Aggregate.Company.PaymentMethod{
                   slug: "paypal",
                   name: "PayPal",
                   method: "gateway",
                   details: "Account myaccount@paypal.com"
                 }
               }
             } == Conta.Aggregate.Company.apply(company, event)
    end

    test "updating payment method successfully" do
      company = %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES",
        payment_methods: %{
          "paypal" => %Conta.Aggregate.Company.PaymentMethod{
            slug: "paypal",
            name: "PayPal",
            method: "gateway",
            details: "Account myaccount@paypal.com"
          }
        }
      }

      command = %Conta.Command.SetPaymentMethod{
        nif: "A55666777",
        slug: "paypal",
        name: "Paypal",
        method: :gateway,
        details: "Account business@paypal.com"
      }

      event = Conta.Aggregate.Company.execute(company, command)

      assert %Conta.Event.PaymentMethodSet{
               nif: "A55666777",
               slug: "paypal",
               name: "Paypal",
               method: "gateway",
               details: "Account business@paypal.com"
             } == event

      assert %Conta.Aggregate.Company{
               nif: "A55666777",
               name: "Great Company SA",
               address: "My Full Address",
               postcode: "28000",
               city: "Madrid",
               state: "Madrid",
               country: "ES",
               payment_methods: %{
                 "paypal" => %Conta.Aggregate.Company.PaymentMethod{
                   slug: "paypal",
                   name: "Paypal",
                   method: "gateway",
                   details: "Account business@paypal.com"
                 }
               }
             } == Conta.Aggregate.Company.apply(company, event)
    end
  end

  describe "invoice" do
    test "update failed because missing invoice" do
      company = %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES",
        contacts: %{
          "B123456789" => %Conta.Aggregate.Company.Contact{
            name: "My client",
            nif: "B123456789",
            address: "My client's address",
            postcode: "14000",
            city: "Cordoba",
            state: "Cordoba",
            country: "ES"
          }
        },
        payment_methods: %{
          "paypal" => %Conta.Aggregate.Company.PaymentMethod{
            name: "PayPal",
            method: "gateway",
            details: "myaccount@paypal.com"
          }
        }
      }

      command = %Conta.Command.SetInvoice{
        action: :update,
        nif: "A55666777",
        client_nif: "B123456789",
        invoice_number: 1,
        invoice_date: Date.new!(2023, 12, 20),
        type: :service,
        subtotal_price: Decimal.new("100.00"),
        tax_price: Decimal.new("21.00"),
        total_price: Decimal.new("121.00"),
        currency: "EUR",
        payment_method: "paypal",
        details: [
          %Conta.Command.SetInvoice.Detail{
            description: "Consultancy",
            tax: 21,
            base_price: Decimal.new("100.00"),
            tax_price: Decimal.new("21.00"),
            total_price: Decimal.new("121.00")
          }
        ]
      }

      assert {:error, %{invoice_number: ["can't be found for update"]}} =
               Conta.Aggregate.Company.execute(company, command)
    end

    test "create failed because missing payment method" do
      company = %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES",
        contacts: %{
          "B123456789" => %Conta.Aggregate.Company.Contact{
            name: "My client",
            nif: "B123456789",
            address: "My client's address",
            postcode: "14000",
            city: "Cordoba",
            state: "Cordoba",
            country: "ES"
          }
        },
        payment_methods: %{
          "paypal" => %Conta.Aggregate.Company.PaymentMethod{
            name: "PayPal",
            method: "gateway",
            details: "myaccount@paypal.com"
          }
        }
      }

      command = %Conta.Command.SetInvoice{
        action: :insert,
        nif: "A55666777",
        client_nif: "B123456789",
        invoice_number: 1,
        invoice_date: Date.new!(2023, 12, 20),
        type: :service,
        subtotal_price: Decimal.new("100.00"),
        tax_price: Decimal.new("21.00"),
        total_price: Decimal.new("121.00"),
        currency: "EUR",
        payment_method: "stripe",
        details: [
          %Conta.Command.SetInvoice.Detail{
            description: "Consultancy",
            tax: 21,
            base_price: Decimal.new("100.00"),
            tax_price: Decimal.new("21.00"),
            total_price: Decimal.new("121.00")
          }
        ]
      }

      assert {:error, %{payment_method: ["is invalid"]}} = Conta.Aggregate.Company.execute(company, command)
    end

    test "create failed because missing contact" do
      company = %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES",
        contacts: %{
          "B123456789" => %Conta.Aggregate.Company.Contact{
            name: "My client",
            nif: "B123456789",
            address: "My client's address",
            postcode: "14000",
            city: "Cordoba",
            state: "Cordoba",
            country: "ES"
          }
        },
        payment_methods: %{
          "paypal" => %Conta.Aggregate.Company.PaymentMethod{
            name: "PayPal",
            method: "gateway",
            details: "myaccount@paypal.com"
          }
        }
      }

      command = %Conta.Command.SetInvoice{
        action: :insert,
        nif: "A55666777",
        client_nif: "A123456789",
        invoice_number: 1,
        invoice_date: Date.new!(2023, 12, 20),
        type: :service,
        subtotal_price: Decimal.new("100.00"),
        tax_price: Decimal.new("21.00"),
        total_price: Decimal.new("121.00"),
        currency: "EUR",
        payment_method: "paypal",
        details: [
          %Conta.Command.SetInvoice.Detail{
            description: "Consultancy",
            tax: 21,
            base_price: Decimal.new("100.00"),
            tax_price: Decimal.new("21.00"),
            total_price: Decimal.new("121.00")
          }
        ]
      }

      assert {:error, %{client_nif: ["is invalid"]}} = Conta.Aggregate.Company.execute(company, command)
    end

    test "create successfully the first of the year" do
      company = %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES",
        contacts: %{
          "B123456789" => %Conta.Aggregate.Company.Contact{
            name: "My client",
            nif: "B123456789",
            address: "My client's address",
            postcode: "14000",
            city: "Cordoba",
            state: "Cordoba",
            country: "ES"
          }
        },
        payment_methods: %{
          "paypal" => %Conta.Aggregate.Company.PaymentMethod{
            name: "PayPal",
            method: "gateway",
            details: "myaccount@paypal.com"
          }
        }
      }

      command = %Conta.Command.SetInvoice{
        action: :insert,
        nif: "A55666777",
        client_nif: "B123456789",
        invoice_number: 1,
        invoice_date: Date.new!(2023, 12, 20),
        type: :service,
        subtotal_price: Decimal.new("100.00"),
        tax_price: Decimal.new("21.00"),
        total_price: Decimal.new("121.00"),
        currency: "EUR",
        payment_method: "paypal",
        details: [
          %Conta.Command.SetInvoice.Detail{
            description: "Consultancy",
            tax: 21,
            base_price: Decimal.new("100.00"),
            tax_price: Decimal.new("21.00"),
            total_price: Decimal.new("121.00")
          }
        ]
      }

      event = Conta.Aggregate.Company.execute(company, command)

      assert %Conta.Event.InvoiceSet{
               action: :insert,
               invoice_number: 1,
               invoice_date: Date.new!(2023, 12, 20),
               type: :service,
               subtotal_price: Decimal.new("100.00"),
               tax_price: Decimal.new("21.00"),
               total_price: Decimal.new("121.00"),
               currency: "EUR",
               destination_country: "ES",
               payment_method: %Conta.Event.Common.PaymentMethod{
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
                   base_price: Decimal.new("100.00"),
                   tax_price: Decimal.new("21.00"),
                   total_price: Decimal.new("121.00")
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
             } == event

      assert %Conta.Aggregate.Company{
               nif: "A55666777",
               name: "Great Company SA",
               address: "My Full Address",
               postcode: "28000",
               city: "Madrid",
               state: "Madrid",
               country: "ES",
               invoice_numbers: %{2023 => MapSet.new([1])},
               template_names: MapSet.new(["default"]),
               contacts: %{
                 "B123456789" => %Conta.Aggregate.Company.Contact{
                   nif: "B123456789",
                   name: "My client",
                   address: "My client's address",
                   postcode: "14000",
                   city: "Cordoba",
                   state: "Cordoba",
                   country: "ES"
                 }
               },
               payment_methods: %{
                 "paypal" => %Conta.Aggregate.Company.PaymentMethod{
                   name: "PayPal",
                   method: "gateway",
                   details: "myaccount@paypal.com"
                 }
               }
             } == Conta.Aggregate.Company.apply(company, event)
    end

    test "update successfully from client to simple" do
      company = %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES",
        invoice_numbers: %{2023 => MapSet.new([1])},
        contacts: %{
          "B123456789" => %Conta.Aggregate.Company.Contact{
            name: "My client",
            nif: "B123456789",
            address: "My client's address",
            postcode: "14000",
            city: "Cordoba",
            state: "Cordoba",
            country: "ES"
          }
        },
        payment_methods: %{
          "paypal" => %Conta.Aggregate.Company.PaymentMethod{
            name: "PayPal",
            method: "gateway",
            details: "myaccount@paypal.com"
          }
        }
      }

      command = %Conta.Command.SetInvoice{
        action: :update,
        nif: "A55666777",
        invoice_number: 1,
        invoice_date: Date.new!(2023, 12, 20),
        type: :service,
        subtotal_price: Decimal.new("100.00"),
        tax_price: Decimal.new("21.00"),
        total_price: Decimal.new("121.00"),
        currency: "EUR",
        destination_country: "ES",
        payment_method: "paypal",
        details: [
          %Conta.Command.SetInvoice.Detail{
            description: "Consultancy",
            tax: 21,
            base_price: Decimal.new("100.00"),
            tax_price: Decimal.new("21.00"),
            total_price: Decimal.new("121.00")
          }
        ]
      }

      event = Conta.Aggregate.Company.execute(company, command)

      assert %Conta.Event.InvoiceSet{
               action: :update,
               invoice_number: 1,
               invoice_date: Date.new!(2023, 12, 20),
               type: :service,
               subtotal_price: Decimal.new("100.00"),
               tax_price: Decimal.new("21.00"),
               total_price: Decimal.new("121.00"),
               currency: "EUR",
               destination_country: "ES",
               payment_method: %Conta.Event.Common.PaymentMethod{
                 name: "PayPal",
                 method: "gateway",
                 details: "myaccount@paypal.com"
               },
               details: [
                 %Conta.Event.InvoiceSet.Detail{
                   description: "Consultancy",
                   tax: 21,
                   base_price: Decimal.new("100.00"),
                   tax_price: Decimal.new("21.00"),
                   total_price: Decimal.new("121.00")
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
             } == event

      assert %Conta.Aggregate.Company{
               nif: "A55666777",
               name: "Great Company SA",
               address: "My Full Address",
               postcode: "28000",
               city: "Madrid",
               state: "Madrid",
               country: "ES",
               invoice_numbers: %{2023 => MapSet.new([1])},
               template_names: MapSet.new(["default"]),
               contacts: %{
                 "B123456789" => %Conta.Aggregate.Company.Contact{
                   nif: "B123456789",
                   name: "My client",
                   address: "My client's address",
                   postcode: "14000",
                   city: "Cordoba",
                   state: "Cordoba",
                   country: "ES"
                 }
               },
               payment_methods: %{
                 "paypal" => %Conta.Aggregate.Company.PaymentMethod{
                   name: "PayPal",
                   method: "gateway",
                   details: "myaccount@paypal.com"
                 }
               }
             } == Conta.Aggregate.Company.apply(company, event)
    end

    test "create simple successfully the first of the year" do
      company = %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES",
        payment_methods: %{
          "paypal" => %Conta.Aggregate.Company.PaymentMethod{
            name: "PayPal",
            method: "gateway",
            details: "myaccount@paypal.com"
          }
        }
      }

      command = %Conta.Command.SetInvoice{
        action: :insert,
        nif: "A55666777",
        invoice_number: 1,
        invoice_date: Date.new!(2023, 12, 20),
        type: :service,
        subtotal_price: Decimal.new("100.00"),
        tax_price: Decimal.new("21.00"),
        total_price: Decimal.new("121.00"),
        currency: "EUR",
        destination_country: "ES",
        payment_method: "paypal",
        details: [
          %Conta.Command.SetInvoice.Detail{
            description: "Consultancy",
            tax: 21,
            base_price: Decimal.new("100.00"),
            tax_price: Decimal.new("21.00"),
            total_price: Decimal.new("121.00")
          }
        ]
      }

      event = Conta.Aggregate.Company.execute(company, command)

      assert %Conta.Event.InvoiceSet{
               action: :insert,
               invoice_number: 1,
               invoice_date: Date.new!(2023, 12, 20),
               type: :service,
               subtotal_price: Decimal.new("100.00"),
               tax_price: Decimal.new("21.00"),
               total_price: Decimal.new("121.00"),
               currency: "EUR",
               destination_country: "ES",
               payment_method: %Conta.Event.Common.PaymentMethod{
                 name: "PayPal",
                 method: "gateway",
                 details: "myaccount@paypal.com"
               },
               client: nil,
               details: [
                 %Conta.Event.InvoiceSet.Detail{
                   description: "Consultancy",
                   tax: 21,
                   base_price: Decimal.new("100.00"),
                   tax_price: Decimal.new("21.00"),
                   total_price: Decimal.new("121.00")
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
             } == event

      assert %Conta.Aggregate.Company{
               nif: "A55666777",
               name: "Great Company SA",
               address: "My Full Address",
               postcode: "28000",
               city: "Madrid",
               state: "Madrid",
               country: "ES",
               invoice_numbers: %{2023 => MapSet.new([1])},
               template_names: MapSet.new(["default"]),
               payment_methods: %{
                 "paypal" => %Conta.Aggregate.Company.PaymentMethod{
                   name: "PayPal",
                   method: "gateway",
                   details: "myaccount@paypal.com"
                 }
               }
             } == Conta.Aggregate.Company.apply(company, event)
    end
  end

  describe "expense" do
    test "update failed because missing expense" do
      company = %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES",
        contacts: %{
          "B123456789" => %Conta.Aggregate.Company.Contact{
            name: "My client",
            nif: "B123456789",
            address: "My client's address",
            postcode: "14000",
            city: "Cordoba",
            state: "Cordoba",
            country: "ES"
          }
        },
        payment_methods: %{
          "paypal" => %Conta.Aggregate.Company.PaymentMethod{
            name: "PayPal",
            method: "gateway",
            details: "myaccount@paypal.com"
          }
        }
      }

      command = %Conta.Command.SetExpense{
        action: :update,
        nif: "A55666777",
        provider_nif: "B123456789",
        invoice_number: "1",
        invoice_date: Date.new!(2023, 12, 20),
        category: :computers,
        subtotal_price: Decimal.new("100.00"),
        tax_price: Decimal.new("21.00"),
        total_price: Decimal.new("121.00"),
        currency: "EUR",
        payment_method: "paypal"
      }

      assert {:error, %{invoice_number: ["does not exist"]}} =
               Conta.Aggregate.Company.execute(company, command)
    end

    test "create failed because missing payment method" do
      company = %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES",
        contacts: %{
          "B123456789" => %Conta.Aggregate.Company.Contact{
            name: "My client",
            nif: "B123456789",
            address: "My client's address",
            postcode: "14000",
            city: "Cordoba",
            state: "Cordoba",
            country: "ES"
          }
        },
        payment_methods: %{
          "paypal" => %Conta.Aggregate.Company.PaymentMethod{
            name: "PayPal",
            method: "gateway",
            details: "myaccount@paypal.com"
          }
        }
      }

      command = %Conta.Command.SetExpense{
        action: :insert,
        nif: "A55666777",
        provider_nif: "B123456789",
        invoice_number: "1",
        invoice_date: Date.new!(2023, 12, 20),
        category: :computers,
        subtotal_price: Decimal.new("100.00"),
        tax_price: Decimal.new("21.00"),
        total_price: Decimal.new("121.00"),
        currency: "EUR",
        payment_method: "stripe"
      }

      assert {:error, %{payment_method: ["is invalid"]}} = Conta.Aggregate.Company.execute(company, command)
    end

    test "create failed because missing contact" do
      company = %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES",
        contacts: %{
          "B123456789" => %Conta.Aggregate.Company.Contact{
            name: "My client",
            nif: "B123456789",
            address: "My client's address",
            postcode: "14000",
            city: "Cordoba",
            state: "Cordoba",
            country: "ES"
          }
        },
        payment_methods: %{
          "paypal" => %Conta.Aggregate.Company.PaymentMethod{
            name: "PayPal",
            method: "gateway",
            details: "myaccount@paypal.com"
          }
        }
      }

      command = %Conta.Command.SetExpense{
        action: :insert,
        nif: "A55666777",
        provider_nif: "A123456789",
        invoice_number: "1",
        invoice_date: Date.new!(2023, 12, 20),
        category: :computers,
        subtotal_price: Decimal.new("100.00"),
        tax_price: Decimal.new("21.00"),
        total_price: Decimal.new("121.00"),
        currency: "EUR",
        payment_method: "paypal"
      }

      assert {:error, %{provider_nif: ["is invalid"]}} = Conta.Aggregate.Company.execute(company, command)
    end

    test "create successfully the first of the year" do
      company = %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES",
        contacts: %{
          "B123456789" => %Conta.Aggregate.Company.Contact{
            name: "My provider",
            nif: "B123456789",
            address: "My provider's address",
            postcode: "14000",
            city: "Cordoba",
            state: "Cordoba",
            country: "ES"
          }
        },
        payment_methods: %{
          "paypal" => %Conta.Aggregate.Company.PaymentMethod{
            name: "PayPal",
            method: "gateway",
            details: "myaccount@paypal.com"
          }
        }
      }

      command = %Conta.Command.SetExpense{
        action: :insert,
        nif: "A55666777",
        provider_nif: "B123456789",
        invoice_number: "1",
        invoice_date: Date.new!(2023, 12, 20),
        category: :computers,
        subtotal_price: Decimal.new("100.00"),
        tax_price: Decimal.new("21.00"),
        total_price: Decimal.new("121.00"),
        currency: "EUR",
        payment_method: "paypal"
      }

      event = Conta.Aggregate.Company.execute(company, command)

      assert %Conta.Event.ExpenseSet{
               action: :insert,
               invoice_number: "1",
               invoice_date: Date.new!(2023, 12, 20),
               category: "computers",
               subtotal_price: Decimal.new("100.00"),
               tax_price: Decimal.new("21.00"),
               total_price: Decimal.new("121.00"),
               currency: "EUR",
               payment_method: %Conta.Event.Common.PaymentMethod{
                 name: "PayPal",
                 method: "gateway",
                 details: "myaccount@paypal.com"
               },
               provider: %Conta.Event.ExpenseSet.Provider{
                 name: "My provider",
                 nif: "B123456789",
                 address: "My provider's address",
                 postcode: "14000",
                 city: "Cordoba",
                 state: "Cordoba",
                 country: "ES"
               },
               company: %Conta.Event.Common.Company{
                 nif: "A55666777",
                 name: "Great Company SA",
                 address: "My Full Address",
                 postcode: "28000",
                 city: "Madrid",
                 state: "Madrid",
                 country: "ES"
               }
             } == event

      assert %Conta.Aggregate.Company{
               nif: "A55666777",
               name: "Great Company SA",
               address: "My Full Address",
               postcode: "28000",
               city: "Madrid",
               state: "Madrid",
               country: "ES",
               expense_numbers: %{2023 => MapSet.new([{"B123456789", "1"}])},
               contacts: %{
                 "B123456789" => %Conta.Aggregate.Company.Contact{
                   nif: "B123456789",
                   name: "My provider",
                   address: "My provider's address",
                   postcode: "14000",
                   city: "Cordoba",
                   state: "Cordoba",
                   country: "ES"
                 }
               },
               payment_methods: %{
                 "paypal" => %Conta.Aggregate.Company.PaymentMethod{
                   name: "PayPal",
                   method: "gateway",
                   details: "myaccount@paypal.com"
                 }
               }
             } == Conta.Aggregate.Company.apply(company, event)
    end

    test "update successfully" do
      company = %Conta.Aggregate.Company{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        state: "Madrid",
        country: "ES",
        expense_numbers: %{2023 => MapSet.new([{"B123456789", "1"}])},
        contacts: %{
          "B123456789" => %Conta.Aggregate.Company.Contact{
            name: "My provider",
            nif: "B123456789",
            address: "My provider's address",
            postcode: "14000",
            city: "Cordoba",
            state: "Cordoba",
            country: "ES"
          }
        },
        payment_methods: %{
          "paypal" => %Conta.Aggregate.Company.PaymentMethod{
            name: "PayPal",
            method: "gateway",
            details: "myaccount@paypal.com"
          }
        }
      }

      command = %Conta.Command.SetExpense{
        action: :update,
        nif: "A55666777",
        provider_nif: "B123456789",
        invoice_number: "1",
        invoice_date: Date.new!(2023, 12, 20),
        category: :computers,
        subtotal_price: Decimal.new("100.00"),
        tax_price: Decimal.new("21.00"),
        total_price: Decimal.new("121.00"),
        currency: "EUR",
        payment_method: "paypal"
      }

      event = Conta.Aggregate.Company.execute(company, command)

      assert %Conta.Event.ExpenseSet{
               action: :update,
               invoice_number: "1",
               invoice_date: Date.new!(2023, 12, 20),
               category: "computers",
               subtotal_price: Decimal.new("100.00"),
               tax_price: Decimal.new("21.00"),
               total_price: Decimal.new("121.00"),
               currency: "EUR",
               payment_method: %Conta.Event.Common.PaymentMethod{
                 name: "PayPal",
                 method: "gateway",
                 details: "myaccount@paypal.com"
               },
               provider: %Conta.Event.ExpenseSet.Provider{
                 name: "My provider",
                 nif: "B123456789",
                 intracommunity: false,
                 address: "My provider's address",
                 postcode: "14000",
                 city: "Cordoba",
                 state: "Cordoba",
                 country: "ES"
               },
               company: %Conta.Event.Common.Company{
                 nif: "A55666777",
                 name: "Great Company SA",
                 address: "My Full Address",
                 postcode: "28000",
                 city: "Madrid",
                 state: "Madrid",
                 country: "ES"
               }
             } == event

      assert %Conta.Aggregate.Company{
               nif: "A55666777",
               name: "Great Company SA",
               address: "My Full Address",
               postcode: "28000",
               city: "Madrid",
               state: "Madrid",
               country: "ES",
               expense_numbers: %{2023 => MapSet.new([{"B123456789", "1"}])},
               contacts: %{
                 "B123456789" => %Conta.Aggregate.Company.Contact{
                   nif: "B123456789",
                   name: "My provider",
                   address: "My provider's address",
                   postcode: "14000",
                   city: "Cordoba",
                   state: "Cordoba",
                   country: "ES"
                 }
               },
               payment_methods: %{
                 "paypal" => %Conta.Aggregate.Company.PaymentMethod{
                   name: "PayPal",
                   method: "gateway",
                   details: "myaccount@paypal.com"
                 }
               }
             } == Conta.Aggregate.Company.apply(company, event)
    end
  end
end
