defmodule Conta.BookTest do
  use Conta.DataCase
  import Conta.BookFixtures

  alias Conta.Book
  alias Conta.Projector.Book.Invoice
  alias Conta.Projector.Book.PaymentMethod

  describe "invoices" do
    test "list_invoices/0 returns all invoices" do
      invoice = insert(:invoice)
      assert [loaded] = Book.list_invoices()
      assert loaded.id == invoice.id
    end

    test "list_invoices/2 with limit and offset" do
      insert(:invoice, %{invoice_number: "2023-00001"})
      insert(:invoice, %{invoice_number: "2023-00002"})
      assert [_] = Book.list_invoices(1, 0)
      assert [_] = Book.list_invoices(1, 1)
      assert [] = Book.list_invoices(1, 2)
    end

    test "list_invoices_by_term_and_year/2 filters by year" do
      insert(:invoice, %{invoice_date: ~D[2023-06-15], invoice_number: "2023-00001"})
      insert(:invoice, %{invoice_date: ~D[2022-06-15], invoice_number: "2022-00001"})
      result = Book.list_invoices_by_term_and_year(nil, "2023")
      assert length(result) == 1
      assert hd(result).invoice_number == "2023-00001"
    end

    test "list_invoices_by_term_and_year/2 filters by term" do
      insert(:invoice, %{invoice_date: ~D[2023-03-15], invoice_number: "2023-00001"})
      insert(:invoice, %{invoice_date: ~D[2023-07-15], invoice_number: "2023-00002"})
      result = Book.list_invoices_by_term_and_year("Q1", nil)
      assert length(result) == 1
      assert hd(result).invoice_number == "2023-00001"
    end

    test "list_invoices_filtered/1 with status paid" do
      insert(:invoice, %{invoice_number: "2023-00001", paid_date: ~D[2023-12-31]})
      insert(:invoice, %{invoice_number: "2023-00002"})
      result = Book.list_invoices_filtered(status: "paid")
      assert length(result) == 1
      assert hd(result).invoice_number == "2023-00001"
    end

    test "list_invoices_filtered/1 with status unpaid" do
      insert(:invoice, %{invoice_number: "2023-00001", paid_date: ~D[2023-12-31]})
      insert(:invoice, %{invoice_number: "2023-00002"})
      result = Book.list_invoices_filtered(status: "unpaid")
      assert length(result) == 1
      assert hd(result).invoice_number == "2023-00002"
    end

    test "list_invoices_filtered/2 respects the limit" do
      insert(:invoice, %{invoice_number: "2023-00001"})
      insert(:invoice, %{invoice_number: "2023-00002"})
      insert(:invoice, %{invoice_number: "2023-00003"})

      assert length(Book.list_invoices_filtered([], 2)) == 2
      assert length(Book.list_invoices_filtered([])) == 3
    end

    test "get_invoice!/1 returns the invoice" do
      invoice = insert(:invoice)
      assert %Invoice{id: id} = Book.get_invoice!(invoice.id)
      assert id == invoice.id
    end

    test "get_invoice/1 returns the invoice or nil" do
      invoice = insert(:invoice)
      assert %Invoice{} = Book.get_invoice(invoice.id)
      assert nil == Book.get_invoice(Ecto.UUID.generate())
    end

    test "get_invoice!/2 by year and number" do
      insert(:invoice, %{invoice_number: "2023-00001", invoice_date: ~D[2023-01-10]})
      assert %Invoice{invoice_number: "2023-00001"} = Book.get_invoice!(2023, 1)
    end

    test "get_last_invoice_number/0 returns 0 when no invoices" do
      assert 0 == Book.get_last_invoice_number()
    end

    test "get_last_invoice_number/0 returns last number for current year" do
      this_year = Date.utc_today().year
      num = "#{this_year}-00003"
      insert(:invoice, %{invoice_number: num, invoice_date: Date.utc_today()})
      assert 3 == Book.get_last_invoice_number()
    end

    test "get_invoice_date_range/0 returns nil when no invoices" do
      assert {nil, nil} = Book.get_invoice_date_range()
    end

    test "get_invoice_date_range/0 returns min and max" do
      insert(:invoice, %{invoice_number: "2022-00001", invoice_date: ~D[2022-01-10]})
      insert(:invoice, %{invoice_number: "2023-00001", invoice_date: ~D[2023-06-15]})
      {max, min} = Book.get_invoice_date_range()
      assert max == ~D[2023-06-15]
      assert min == ~D[2022-01-10]
    end

    test "new_set_invoice/0 returns a SetInvoice command" do
      set_invoice = Book.new_set_invoice()
      assert set_invoice.action == :insert
      assert set_invoice.invoice_date == Date.utc_today()
    end

    test "get_set_invoice/1 from id" do
      invoice = insert(:invoice)
      set_invoice = Book.get_set_invoice(invoice.id)
      assert set_invoice.action == :update
      assert set_invoice.invoice_number == 1
    end

    test "get_remove_invoice/1 from id" do
      invoice = insert(:invoice)
      remove = Book.get_remove_invoice(invoice.id)
      assert remove.invoice_number == 1
    end

    test "get_duplicate_invoice/1 creates a new invoice command" do
      insert(:invoice, %{invoice_number: "2023-00001", invoice_date: ~D[2023-01-10]})
      invoice = insert(:invoice, %{invoice_number: "2023-00002", invoice_date: ~D[2023-01-15]})
      dup = Book.get_duplicate_invoice(invoice.id)
      assert dup.action == :insert
      assert dup.invoice_date == Date.utc_today()
    end
  end

  describe "payment methods" do
    test "list_payment_methods/0 returns all methods for default nif" do
      # No payment methods → empty list (nif not configured in test env)
      assert is_list(Book.list_payment_methods("NONEXISTENT"))
    end

    test "list_payment_methods/1 with specific nif" do
      %PaymentMethod{nif: nif} = insert(:payment_method)
      result = Book.list_payment_methods(nif)
      assert length(result) == 1
    end
  end

  describe "templates" do
    test "list_templates/1 returns empty for unknown nif" do
      assert [] = Book.list_templates("NONEXISTENT")
    end
  end
end
