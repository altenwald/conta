defmodule ContaWeb.Api.Book.InvoiceTest do
  use ContaWeb.ConnCase, async: false

  import Conta.BookFixtures

  alias Conta.Accounts
  alias Conta.AccountsFixtures

  setup %{conn: conn} do
    :ok =
      Conta.Commanded.Application.dispatch(%Conta.Command.SetCompany{
        nif: "A55666777",
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        country: "ES"
      })

    :ok =
      Conta.Commanded.Application.dispatch(%Conta.Command.SetPaymentMethod{
        nif: "A55666777",
        name: "PayPal",
        slug: "paypal",
        method: :gateway,
        details: "myaccount@paypal.com"
      })

    user = AccountsFixtures.insert(:user) |> AccountsFixtures.confirm_user()
    token = Accounts.create_user_api_token(user)

    authed_conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> put_req_header("accept", "application/json")

    %{authed_conn: authed_conn, user: user}
  end

  describe "GET /api/v1/books/invoices" do
    test "requires API token", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/books/invoices")
      assert response(conn, 401) =~ "No access for you"
    end

    test "lists all invoices when no filter is provided", %{authed_conn: conn} do
      insert(:invoice, %{invoice_number: "2026-00001"})
      insert(:invoice, %{invoice_number: "2026-00002"})

      conn = get(conn, ~p"/api/v1/books/invoices")
      assert invoices = json_response(conn, 200)
      assert length(invoices) == 2
    end

    test "filters invoices by client NIF via query param", %{authed_conn: conn} do
      client1 = %{invoice_client_factory() | nif: "B11111111"}
      client2 = %{invoice_client_factory() | nif: "B22222222"}

      insert(:invoice, %{invoice_number: "2026-00001", client: client1})
      insert(:invoice, %{invoice_number: "2026-00002", client: client2})

      conn = get(conn, ~p"/api/v1/books/invoices?client_id=B11111111")
      assert invoices = json_response(conn, 200)
      assert length(invoices) == 1
      assert hd(invoices)["invoice_number"] == "2026-00001"
    end

    test "filters invoices by contact UUID via query param", %{authed_conn: conn} do
      contact = Conta.DirectoryFixtures.insert(:contact, %{nif: "B33333333"})
      client1 = %{invoice_client_factory() | nif: "B33333333"}
      client2 = %{invoice_client_factory() | nif: "B44444444"}

      insert(:invoice, %{invoice_number: "2026-00001", client: client1})
      insert(:invoice, %{invoice_number: "2026-00002", client: client2})

      conn = get(conn, ~p"/api/v1/books/invoices?client_id=#{contact.id}")
      assert invoices = json_response(conn, 200)
      assert length(invoices) == 1
      assert hd(invoices)["invoice_number"] == "2026-00001"
    end

    test "filters invoices via nested /clients/:client_id/invoices route", %{authed_conn: conn} do
      contact = Conta.DirectoryFixtures.insert(:contact, %{nif: "B55555555"})
      client1 = %{invoice_client_factory() | nif: "B55555555"}
      client2 = %{invoice_client_factory() | nif: "B66666666"}

      insert(:invoice, %{invoice_number: "2026-00001", client: client1})
      insert(:invoice, %{invoice_number: "2026-00002", client: client2})

      conn = get(conn, ~p"/api/v1/books/clients/#{contact.id}/invoices")
      assert invoices = json_response(conn, 200)
      assert length(invoices) == 1
      assert hd(invoices)["invoice_number"] == "2026-00001"
    end

    test "combines client filter with term and year", %{authed_conn: conn} do
      client = %{invoice_client_factory() | nif: "B11111111"}

      insert(:invoice, %{
        invoice_number: "2026-00001",
        invoice_date: ~D[2026-02-15],
        client: client
      })

      insert(:invoice, %{
        invoice_number: "2026-00002",
        invoice_date: ~D[2026-05-15],
        client: client
      })

      conn = get(conn, ~p"/api/v1/books/invoices?client_id=B11111111&year=2026&term=Q1")
      assert invoices = json_response(conn, 200)
      assert length(invoices) == 1
      assert hd(invoices)["invoice_number"] == "2026-00001"
    end

    test "returns empty list when no invoices match client", %{authed_conn: conn} do
      insert(:invoice, %{invoice_number: "2026-00001"})

      conn = get(conn, ~p"/api/v1/books/invoices?client_id=NONEXISTENT")
      assert json_response(conn, 200) == []
    end
  end

  describe "GET /api/v1/books/invoices/:id/download" do
    test "requires API token", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/books/invoices/#{Ecto.UUID.generate()}/download")
      assert response(conn, 401) =~ "No access for you"
    end

    test "returns 404 when invoice does not exist", %{authed_conn: conn} do
      conn = get(conn, ~p"/api/v1/books/invoices/#{Ecto.UUID.generate()}/download")
      assert %{"errors" => %{"id" => "invoice not found"}} = json_response(conn, 404)
    end

    test "downloads invoice as PDF", %{authed_conn: conn} do
      invoice =
        insert(:invoice, %{
          invoice_number: "2026-00001",
          company: %{invoice_company_factory() | nif: "A55666777"},
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

      conn = get(conn, ~p"/api/v1/books/invoices/#{invoice.id}/download")

      assert response_content_type(conn, :pdf)

      assert get_resp_header(conn, "content-disposition") == [
               "attachment; filename=2026-00001.pdf"
             ]

      pdf = response(conn, 200)
      assert String.starts_with?(pdf, "%PDF-1.4")
      assert String.ends_with?(pdf, "%%EOF")
    end
  end

  describe "GET /api/v1/books/invoices/:id" do
    test "shows invoice when exists", %{authed_conn: conn} do
      invoice = insert(:invoice, %{invoice_number: "2026-00001"})
      conn = get(conn, ~p"/api/v1/books/invoices/#{invoice.id}")
      assert %{"invoice_number" => "2026-00001"} = json_response(conn, 200)
    end

    test "returns 404 when invoice does not exist", %{authed_conn: conn} do
      conn = get(conn, ~p"/api/v1/books/invoices/#{Ecto.UUID.generate()}")
      assert %{"errors" => %{"id" => "invoice not found"}} = json_response(conn, 404)
    end
  end

  describe "POST /api/v1/books/invoices" do
    test "returns 400 when params are invalid", %{authed_conn: conn} do
      conn = post(conn, ~p"/api/v1/books/invoices", %{})
      assert %{"errors" => _} = json_response(conn, 400)
    end
  end

  describe "POST /api/v1/books/invoices/:id/credit_note" do
    test "creates a credit note from an invoice", %{authed_conn: conn} do
      Phoenix.PubSub.subscribe(Conta.PubSub, "event:invoice_set")

      invoice =
        insert(:invoice, %{
          invoice_number: "2026-00001",
          company: %{invoice_company_factory() | nif: "A55666777"}
        })

      conn = post(conn, ~p"/api/v1/books/invoices/#{invoice.id}/credit_note")
      assert %{"status" => "ok"} = json_response(conn, 201)

      assert_receive {:invoice_set, _credit_note}, 1500
    end

    test "returns 404 when invoice does not exist", %{authed_conn: conn} do
      conn = post(conn, ~p"/api/v1/books/invoices/#{Ecto.UUID.generate()}/credit_note")
      assert %{"errors" => %{"id" => "invoice not found"}} = json_response(conn, 404)
    end
  end

  describe "DELETE /api/v1/books/invoices/:id" do
    test "returns 404 when invoice does not exist", %{authed_conn: conn} do
      conn = delete(conn, ~p"/api/v1/books/invoices/#{Ecto.UUID.generate()}")
      assert %{"errors" => %{"id" => "invoice not found"}} = json_response(conn, 404)
    end
  end
end
