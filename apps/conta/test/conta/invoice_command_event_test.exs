defmodule Conta.InvoiceCommandEventTest do
  use ExUnit.Case, async: true

  alias Conta.Command.SetInvoice
  alias Conta.Event.InvoiceSet

  describe "Conta.Command.SetInvoice" do
    test "casts optional :id when provided" do
      uuid = Ecto.UUID.generate()

      params = %{
        "id" => uuid,
        "action" => "insert",
        "nif" => "A12345678",
        "invoice_date" => ~D[2026-09-07],
        "currency" => "EUR",
        "type" => "service",
        "subtotal_price" => "100.00",
        "tax_price" => "21.00",
        "total_price" => "121.00",
        "payment_method" => "bank_transfer",
        "destination_country" => "ES",
        "details" => [
          %{
            "description" => "Development",
            "tax" => 21,
            "base_price" => "100.00",
            "tax_price" => "21.00",
            "total_price" => "121.00"
          }
        ]
      }

      changeset = SetInvoice.changeset(%SetInvoice{}, params)
      assert changeset.valid?
      command = SetInvoice.to_command(changeset)
      assert command.id == uuid
    end

    test "allows :id to be nil when not provided" do
      params = %{
        "action" => "insert",
        "nif" => "A12345678",
        "invoice_date" => ~D[2026-09-07],
        "currency" => "EUR",
        "type" => "service",
        "subtotal_price" => "100.00",
        "tax_price" => "21.00",
        "total_price" => "121.00",
        "payment_method" => "bank_transfer",
        "destination_country" => "ES",
        "details" => [
          %{
            "description" => "Development",
            "tax" => 21,
            "base_price" => "100.00",
            "tax_price" => "21.00",
            "total_price" => "121.00"
          }
        ]
      }

      changeset = SetInvoice.changeset(%SetInvoice{}, params)
      assert changeset.valid?
      command = SetInvoice.to_command(changeset)
      assert command.id == nil
    end
  end

  describe "Conta.Event.InvoiceSet" do
    test "casts optional :id when provided" do
      uuid = Ecto.UUID.generate()

      params = %{
        "id" => uuid,
        "action" => :insert,
        "invoice_number" => 1,
        "invoice_date" => ~D[2026-09-07],
        "type" => :service,
        "subtotal_price" => Decimal.new("100.00"),
        "tax_price" => Decimal.new("21.00"),
        "total_price" => Decimal.new("121.00"),
        "currency" => "EUR",
        "company" => %{
          "nif" => "A12345678",
          "name" => "My Company",
          "address" => "Main Street 1",
          "postcode" => "28001",
          "city" => "Madrid",
          "country" => "ES"
        },
        "details" => [
          %{
            "description" => "Development",
            "tax" => 21,
            "base_price" => Decimal.new("100.00"),
            "tax_price" => Decimal.new("21.00"),
            "total_price" => Decimal.new("121.00")
          }
        ]
      }

      assert %InvoiceSet{id: ^uuid} = InvoiceSet.changeset(%InvoiceSet{}, params)
    end

    test "allows :id to be nil when not provided" do
      params = %{
        "action" => :insert,
        "invoice_number" => 1,
        "invoice_date" => ~D[2026-09-07],
        "type" => :service,
        "subtotal_price" => Decimal.new("100.00"),
        "tax_price" => Decimal.new("21.00"),
        "total_price" => Decimal.new("121.00"),
        "currency" => "EUR",
        "company" => %{
          "nif" => "A12345678",
          "name" => "My Company",
          "address" => "Main Street 1",
          "postcode" => "28001",
          "city" => "Madrid",
          "country" => "ES"
        },
        "details" => [
          %{
            "description" => "Development",
            "tax" => 21,
            "base_price" => Decimal.new("100.00"),
            "tax_price" => Decimal.new("21.00"),
            "total_price" => Decimal.new("121.00")
          }
        ]
      }

      assert %InvoiceSet{id: nil} = InvoiceSet.changeset(%InvoiceSet{}, params)
    end
  end
end
