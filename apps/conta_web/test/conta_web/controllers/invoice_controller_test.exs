defmodule ContaWeb.InvoiceControllerTest do
  use ContaWeb.ConnCase

  import Conta.AutomatorFixtures

  alias Conta.AccountsFixtures

  setup do
    %{user: AccountsFixtures.insert(:user) |> AccountsFixtures.confirm_user()}
  end

  describe "GET /books/invoices/run/:automator_id" do
    test "runs the filter, injecting real invoices under the registry key", %{conn: conn, user: user} do
      filter =
        insert(:filter, %{
          type: :invoice,
          output: :json,
          code: "return #invoices",
          params: [build(:filter_param, %{name: "invoices", type: :table})]
        })

      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/books/invoices/run/#{filter.id}")

      assert response(conn, 200) =~ ~r/^\d+$/
    end
  end

  describe "GET /books/invoices/:id/download" do
    test "renders invoice as a PDF binary using Press", %{conn: conn, user: user} do
      invoice =
        Conta.BookFixtures.insert(:invoice, %{
          invoice_number: "2026-00001",
          company: %{Conta.BookFixtures.invoice_company_factory() | nif: "A55666777"},
          template: "default"
        })

      Conta.Repo.insert!(%Conta.Projector.Book.Template{
        id: Ecto.UUID.generate(),
        nif: "A55666777",
        name: "default",
        css: "h1 { color: blue; }",
        logo: nil,
        logo_mime_type: nil
      })

      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/books/invoices/#{invoice.id}/download")

      assert response_content_type(conn, :pdf)

      assert get_resp_header(conn, "content-disposition") == [
               "attachment; filename=2026-00001.pdf"
             ]

      pdf = response(conn, 200)
      assert String.starts_with?(pdf, "%PDF-1.4")
      assert String.ends_with?(pdf, "%%EOF")
    end

    test "renders credit note as a PDF binary using Press", %{conn: conn, user: user} do
      invoice =
        Conta.BookFixtures.insert(:invoice, %{
          invoice_number: "CN-2026-00001",
          is_credit_note: true,
          origin_invoice_number: "2026-00001",
          origin_invoice_date: ~D[2026-08-20],
          company: %{Conta.BookFixtures.invoice_company_factory() | nif: "A55666777"},
          template: "default"
        })

      Conta.Repo.insert!(%Conta.Projector.Book.Template{
        id: Ecto.UUID.generate(),
        nif: "A55666777",
        name: "default",
        css: "h1 { color: blue; }",
        logo: nil,
        logo_mime_type: nil
      })

      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/books/invoices/#{invoice.id}/download")

      assert response_content_type(conn, :pdf)

      assert get_resp_header(conn, "content-disposition") == [
               "attachment; filename=CN-2026-00001.pdf"
             ]

      pdf = response(conn, 200)
      assert String.starts_with?(pdf, "%PDF-1.4")
      assert String.ends_with?(pdf, "%%EOF")
    end
  end

  describe "GET /books/invoices/:id" do
    test "renders invoice show page with non-printable email delivery history", %{conn: conn, user: user} do
      invoice =
        Conta.BookFixtures.insert(:invoice, %{
          invoice_number: "2026-00001",
          company: %{Conta.BookFixtures.invoice_company_factory() | nif: "A55666777"},
          template: "default"
        })

      Conta.Repo.insert!(%Conta.Projector.Book.Template{
        id: Ecto.UUID.generate(),
        nif: "A55666777",
        name: "default",
        css: "h1 { color: blue; }",
        logo: nil,
        logo_mime_type: nil
      })

      Conta.Repo.insert!(%Conta.Projector.Book.InvoiceEmail{
        id: Ecto.UUID.generate(),
        invoice_id: invoice.id,
        to: "accountant@client.com",
        subject: "Invoice 2026-00001",
        body: "Attached invoice",
        sent_at: ~U[2026-08-28 11:30:00.000000Z]
      })

      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/books/invoices/#{invoice.id}")

      html = response(conn, 200)
      assert html =~ "Email Delivery History"
      assert html =~ "accountant@client.com"
      assert html =~ "2026-08-28"
      assert html =~ "11:30:00"
      assert html =~ "Send by email"
      assert html =~ "Download PDF"
    end

    test "renders invoice show page with no email deliveries yet", %{conn: conn, user: user} do
      invoice =
        Conta.BookFixtures.insert(:invoice, %{
          invoice_number: "2026-00002",
          company: %{Conta.BookFixtures.invoice_company_factory() | nif: "A55666777"},
          template: "default"
        })

      Conta.Repo.insert!(%Conta.Projector.Book.Template{
        id: Ecto.UUID.generate(),
        nif: "A55666777",
        name: "default",
        css: "h1 { color: blue; }",
        logo: nil,
        logo_mime_type: nil
      })

      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/books/invoices/#{invoice.id}")

      html = response(conn, 200)
      assert html =~ "This invoice has not been sent by email yet."
      assert html =~ "Send by email"
      assert html =~ "Download PDF"
    end
  end
end
