defmodule ContaWeb.InvoiceLiveTest do
  use ContaWeb.ConnCase

  import Conta.BookFixtures
  import Phoenix.LiveViewTest

  alias Conta.AccountsFixtures
  alias Conta.Book
  alias Conta.Command.SetCompany
  alias Conta.Command.SetPaymentMethod
  alias Conta.Commanded.Application, as: CommandedApp

  @company_nif "A55666777"

  setup do
    Application.put_env(:conta, :default_company_nif, @company_nif)

    :ok =
      CommandedApp.dispatch(%SetCompany{
        nif: @company_nif,
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        country: "ES"
      })

    :ok =
      CommandedApp.dispatch(%SetPaymentMethod{
        nif: @company_nif,
        name: "Paypal Wallet",
        slug: "paypal",
        method: :gateway,
        details: "myaccount@paypal.com"
      })

    user = AccountsFixtures.insert(:user) |> AccountsFixtures.confirm_user()
    %{user: user}
  end

  describe "Index" do
    test "lists all invoices including credit notes", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      original = insert(:invoice, %{invoice_number: "2026-00001", invoice_date: ~D[2026-08-20]})

      _credit_note =
        insert(:invoice, %{
          invoice_number: "CN-2026-00001",
          invoice_date: ~D[2026-08-26],
          is_credit_note: true,
          origin_invoice_id: original.id,
          origin_invoice_number: original.invoice_number,
          origin_invoice_date: original.invoice_date
        })

      {:ok, _index_live, html} = live(conn, ~p"/books/invoices")

      assert html =~ "2026-00001"
      assert html =~ "CN-2026-00001"
    end

    test "creates credit note from an invoice via LiveView action", %{conn: conn, user: user} do
      Phoenix.PubSub.subscribe(Conta.PubSub, "event:invoice_set")
      conn = log_in_user(conn, user)
      invoice = insert(:invoice, %{invoice_number: "2026-00002", invoice_date: ~D[2026-08-20]})

      {:ok, index_live, html} = live(conn, ~p"/books/invoices")
      assert html =~ "2026-00002"

      # Click create credit note button
      result =
        index_live
        |> element("#books_invoices-#{invoice.id} a[title='Create Credit Note']")
        |> render_click()

      assert result =~ "Credit note created successfully"

      assert_receive {:invoice_set, credit_note}, 1500
      assert credit_note.is_credit_note == true
      assert credit_note.origin_invoice_number == "2026-00002"
      assert credit_note.invoice_number =~ "CN-2026-"

      html = render(index_live)
      assert html =~ credit_note.invoice_number

      # Verify created in Book
      persisted = Book.get_credit_note_by_origin_invoice_id(invoice.id)
      assert persisted != nil
      assert persisted.is_credit_note == true
      assert persisted.origin_invoice_number == "2026-00002"
    end

    test "shows view credit note link when invoice already has a credit note", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      original = insert(:invoice, %{invoice_number: "2026-00003", invoice_date: ~D[2026-08-20]})

      credit_note =
        insert(:invoice, %{
          invoice_number: "CN-2026-00001",
          invoice_date: ~D[2026-08-26],
          is_credit_note: true,
          origin_invoice_id: original.id,
          origin_invoice_number: original.invoice_number,
          origin_invoice_date: original.invoice_date
        })

      {:ok, index_live, html} = live(conn, ~p"/books/invoices")
      assert html =~ "2026-00003"

      assert has_element?(
               index_live,
               "#books_invoices-#{original.id} a[href='/books/invoices/#{credit_note.id}']"
             )
    end

    test "opens send email modal and delivers invoice email", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      client = %{
        invoice_client_factory()
        | nif: "B12345678",
          name: "Client Corp",
          emails: ["client@corp.com"]
      }

      invoice = insert(:invoice, %{invoice_number: "2026-00010", client: client})

      {:ok, index_live, _html} = live(conn, ~p"/books/invoices")

      # Click the send email button for this invoice
      assert index_live
             |> element("#books_invoices-#{invoice.id} a[title='Send by email']")
             |> render_click() =~ "Send Invoice by Email"

      assert_patch(index_live, ~p"/books/invoices/#{invoice.id}/send_email")

      # Modal shows attached invoice and client email checkbox
      assert has_element?(index_live, "#send-email-modal")
      assert has_element?(index_live, "#send-invoice-email-form")
      assert render(index_live) =~ "2026-00010.pdf"
      assert render(index_live) =~ "client@corp.com"

      # Submit the form
      assert index_live
             |> form("#send-invoice-email-form", %{
               subject: "Invoice 2026-00010",
               body: "Dear client, please find attached your invoice."
             })
             |> render_submit()

      assert_patch(index_live, ~p"/books/invoices")
      assert render(index_live) =~ "Invoices sent by email successfully"
    end

    test "send button is disabled when client has no emails and enables upon adding one", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)
      client = %{invoice_client_factory() | nif: "B99998888", name: "No Email Corp", emails: []}
      invoice = insert(:invoice, %{invoice_number: "2026-00099", client: client})

      {:ok, index_live, _html} = live(conn, ~p"/books/invoices")

      index_live
      |> element("#books_invoices-#{invoice.id} a[title='Send by email']")
      |> render_click()

      assert_patch(index_live, ~p"/books/invoices/#{invoice.id}/send_email")

      # Send button is disabled
      html = render(index_live)
      assert html =~ "btn-disabled"
      assert html =~ "No client emails registered in the directory"

      # Add recipient email in input
      index_live
      |> element("input[name='new_recipient']")
      |> render_change(%{"new_recipient" => "fresh@corp.com"})

      index_live
      |> element("button", "Add")
      |> render_click()

      html = render(index_live)
      refute html =~ "btn-disabled"
      assert html =~ "fresh@corp.com"
    end

    test "batch sending enables button when same client, disables when different clients", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)
      client1 = %{invoice_client_factory() | nif: "B11111111", name: "Alpha", emails: ["alpha@test.com"]}
      client2 = %{invoice_client_factory() | nif: "B22222222", name: "Beta", emails: ["beta@test.com"]}

      inv1 = insert(:invoice, %{invoice_number: "2026-00021", client: client1})
      inv2 = insert(:invoice, %{invoice_number: "2026-00022", client: client1})
      inv3 = insert(:invoice, %{invoice_number: "2026-00023", client: client2})

      {:ok, index_live, _html} = live(conn, ~p"/books/invoices")

      # Select inv1 and inv2 (same client)
      index_live |> element("input[phx-value-id='#{inv1.id}']") |> render_click()
      index_live |> element("input[phx-value-id='#{inv2.id}']") |> render_click()

      html = render(index_live)
      assert html =~ "Send 2 by email"
      refute html =~ "All selected invoices must belong to the same client"

      # Now select inv3 (different client) -> becomes disabled
      index_live |> element("input[phx-value-id='#{inv3.id}']") |> render_click()
      html = render(index_live)
      assert html =~ "All selected invoices must belong to the same client"

      # Deselect inv3 -> enabled again
      index_live |> element("input[phx-value-id='#{inv3.id}']") |> render_click()

      # Open batch modal
      assert index_live |> element("a", "Send 2 by email") |> render_click() =~ "Send Invoices by Email"
      assert_patch(index_live, ~p"/books/invoices/send_batch_email")

      # Submit batch email
      assert index_live
             |> form("#send-invoice-email-form", %{
               subject: "Invoices Alpha",
               body: "Please find attached your invoices."
             })
             |> render_submit()

      assert_patch(index_live, ~p"/books/invoices")
      assert render(index_live) =~ "Invoices sent by email successfully"
    end

    test "shows error when trying to add an invalid email in modal", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      invoice = insert(:invoice, %{invoice_number: "2026-00050"})

      {:ok, index_live, _html} = live(conn, ~p"/books/invoices/#{invoice.id}/send_email")

      index_live
      |> element("input[name='new_recipient']")
      |> render_change(%{"new_recipient" => "not-an-email"})

      index_live
      |> element("button", "Add")
      |> render_click()

      assert render(index_live) =~ "Please enter a valid email address"
    end

    test "sends email copy to company when checkbox is checked", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      company = %{
        invoice_company_factory()
        | nif: "A55666777",
          name: "My Company",
          email: "self@company.com"
      }

      client = %{
        invoice_client_factory()
        | nif: "B12345678",
          name: "Client",
          emails: ["client@corp.com"]
      }

      invoice = insert(:invoice, %{invoice_number: "2026-00051", company: company, client: client})

      {:ok, index_live, _html} = live(conn, ~p"/books/invoices/#{invoice.id}/send_email")

      # Toggle company email copy
      index_live
      |> element("input[name='email_toggle[self@company.com]']")
      |> render_click()

      # Submit form
      index_live
      |> form("#send-invoice-email-form", %{
        subject: "Invoice 2026-00051",
        body: "Attached invoice."
      })
      |> render_submit()

      assert_patch(index_live, ~p"/books/invoices")
      assert render(index_live) =~ "client@corp.com, self@company.com"
    end

    test "redirects to index when navigating directly to batch email with no selection", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, index_live, _html} = live(conn, ~p"/books/invoices")

      index_live
      |> element("a", "Invoices")

      render_patch(index_live, ~p"/books/invoices/send_batch_email")
      assert_patch(index_live, ~p"/books/invoices")
    end
  end
end
