defmodule ContaWeb.InvoiceLiveTest do
  use ContaWeb.ConnCase

  import Phoenix.LiveViewTest

  @create_attrs %{}
  @update_attrs %{}
  @invalid_attrs %{}

  defp create_invoice(_) do
    # invoice = invoice_fixture()
    # %{invoice: invoice}
    %{}
  end

  describe "Index" do
    setup [:create_invoice]

    @tag skip: :broken
    test "lists all books_invoices", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/books_invoices")

      assert html =~ "Listing Books invoices"
    end

    @tag skip: :broken
    test "saves new invoice", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/books_invoices")

      assert index_live |> element("a", "New Invoice") |> render_click() =~
               "New Invoice"

      assert_patch(index_live, ~p"/books_invoices/new")

      assert index_live
             |> form("#invoice-form", invoice: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#invoice-form", invoice: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/books_invoices")

      html = render(index_live)
      assert html =~ "Invoice created successfully"
    end

    @tag skip: :broken
    test "updates invoice in listing", %{conn: conn, invoice: invoice} do
      {:ok, index_live, _html} = live(conn, ~p"/books_invoices")

      assert index_live |> element("#books_invoices-#{invoice.id} a", "Edit") |> render_click() =~
               "Edit Invoice"

      assert_patch(index_live, ~p"/books_invoices/#{invoice}/edit")

      assert index_live
             |> form("#invoice-form", invoice: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#invoice-form", invoice: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/books_invoices")

      html = render(index_live)
      assert html =~ "Invoice updated successfully"
    end

    @tag skip: :broken
    test "deletes invoice in listing", %{conn: conn, invoice: invoice} do
      {:ok, index_live, _html} = live(conn, ~p"/books_invoices")

      assert index_live |> element("#books_invoices-#{invoice.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#books_invoices-#{invoice.id}")
    end
  end

  describe "Show" do
    setup [:create_invoice]

    @tag skip: :broken
    test "displays invoice", %{conn: conn, invoice: invoice} do
      {:ok, _show_live, html} = live(conn, ~p"/books_invoices/#{invoice}")

      assert html =~ "Show Invoice"
    end

    @tag skip: :broken
    test "updates invoice within modal", %{conn: conn, invoice: invoice} do
      {:ok, show_live, _html} = live(conn, ~p"/books_invoices/#{invoice}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Invoice"

      assert_patch(show_live, ~p"/books_invoices/#{invoice}/show/edit")

      assert show_live
             |> form("#invoice-form", invoice: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#invoice-form", invoice: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/books_invoices/#{invoice}")

      html = render(show_live)
      assert html =~ "Invoice updated successfully"
    end
  end
end
