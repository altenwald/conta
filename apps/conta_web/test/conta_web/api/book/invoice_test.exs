defmodule ContaWeb.Api.Book.InvoiceTest do
  use ContaWeb.ConnCase

  import Conta.BookFixtures

  alias Conta.Accounts
  alias Conta.AccountsFixtures

  setup %{conn: conn} do
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

    test "filters invoices via nested /contacts/:client_id/invoices route", %{authed_conn: conn} do
      contact = Conta.DirectoryFixtures.insert(:contact, %{nif: "B77777777"})
      client1 = %{invoice_client_factory() | nif: "B77777777"}
      client2 = %{invoice_client_factory() | nif: "B88888888"}

      insert(:invoice, %{invoice_number: "2026-00001", client: client1})
      insert(:invoice, %{invoice_number: "2026-00002", client: client2})

      conn = get(conn, ~p"/api/v1/books/contacts/#{contact.id}/invoices")
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
end
