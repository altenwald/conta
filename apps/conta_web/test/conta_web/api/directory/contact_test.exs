defmodule ContaWeb.Api.Directory.ContactTest do
  use ContaWeb.ConnCase, async: false

  import Conta.DirectoryFixtures

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

    user = AccountsFixtures.insert(:user) |> AccountsFixtures.confirm_user()
    token = Accounts.create_user_api_token(user)

    authed_conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> put_req_header("accept", "application/json")

    %{authed_conn: authed_conn, user: user}
  end

  describe "GET /api/v1/directories/contacts" do
    test "requires API token", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/directories/contacts")
      assert response(conn, 401) =~ "No access for you"
    end

    test "returns empty list when no contacts exist", %{authed_conn: conn} do
      conn = get(conn, ~p"/api/v1/directories/contacts")
      assert json_response(conn, 200) == []
    end

    test "returns list of contacts", %{authed_conn: conn} do
      contact = insert(:contact, company_nif: "A55666777")
      conn = get(conn, ~p"/api/v1/directories/contacts")
      response = json_response(conn, 200)
      assert length(response) == 1
      [item] = response
      assert item["id"] == contact.id
      assert item["name"] == contact.name
      assert item["nif"] == contact.nif
    end
  end

  describe "GET /api/v1/directories/contacts/:id" do
    test "returns contact by id", %{authed_conn: conn} do
      contact = insert(:contact, company_nif: "A55666777")
      conn = get(conn, ~p"/api/v1/directories/contacts/#{contact.id}")
      assert json_response(conn, 200)["id"] == contact.id
    end

    test "returns 404 for nonexistent contact", %{authed_conn: conn} do
      conn = get(conn, ~p"/api/v1/directories/contacts/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)["errors"]["id"] == "contact not found"
    end
  end

  describe "POST /api/v1/directories/contacts" do
    test "creates contact without explicit id and returns id and nif", %{authed_conn: conn} do
      params = %{
        "company_nif" => "A55666777",
        "name" => "Acme Corp",
        "nif" => "B12345678",
        "address" => "Gran Via 1",
        "postcode" => "28013",
        "city" => "Madrid",
        "country" => "ES",
        "emails" => ["billing@acme.com"]
      }

      conn = post(conn, ~p"/api/v1/directories/contacts", params)
      response = json_response(conn, 201)

      assert is_binary(response["id"])
      assert response["nif"] == "B12345678"
    end

    test "creates contact with client-specified id and returns it", %{authed_conn: conn} do
      custom_id = Ecto.UUID.generate()

      params = %{
        "id" => custom_id,
        "company_nif" => "A55666777",
        "name" => "Custom ID Corp",
        "nif" => "B87654321",
        "address" => "Paseo de la Castellana 100",
        "postcode" => "28046",
        "city" => "Madrid",
        "country" => "ES"
      }

      conn = post(conn, ~p"/api/v1/directories/contacts", params)
      response = json_response(conn, 201)

      assert response["id"] == custom_id
      assert response["nif"] == "B87654321"
    end

    test "returns 400 with validation errors when required fields are missing", %{authed_conn: conn} do
      conn = post(conn, ~p"/api/v1/directories/contacts", %{})
      assert json_response(conn, 400)["errors"] != nil
    end
  end

  describe "PUT /api/v1/directories/contacts/:id" do
    test "updates contact and returns id and nif", %{authed_conn: conn} do
      contact = insert(:contact, company_nif: "A55666777", nif: "B55555555", name: "Old Name")

      params = %{
        "name" => "Updated Name",
        "address" => "New Address"
      }

      conn = put(conn, ~p"/api/v1/directories/contacts/#{contact.id}", params)
      response = json_response(conn, 200)

      assert response["id"] == contact.id
      assert response["nif"] == "B55555555"
    end

    test "returns 404 when updating nonexistent contact", %{authed_conn: conn} do
      conn = put(conn, ~p"/api/v1/directories/contacts/#{Ecto.UUID.generate()}", %{"name" => "New"})
      assert json_response(conn, 404)["errors"]["id"] == "contact not found"
    end
  end

  describe "DELETE /api/v1/directories/contacts/:id" do
    test "deletes contact successfully", %{authed_conn: conn} do
      contact_id = Ecto.UUID.generate()

      :ok =
        Conta.Commanded.Application.dispatch(%Conta.Command.SetContact{
          id: contact_id,
          company_nif: "A55666777",
          nif: "B77777777",
          name: "Contact To Delete",
          address: "Address",
          postcode: "12345",
          city: "City",
          country: "ES"
        })

      conn = delete(conn, ~p"/api/v1/directories/contacts/#{contact_id}")
      assert json_response(conn, 200) == "ok"
    end

    test "returns 404 when deleting nonexistent contact", %{authed_conn: conn} do
      conn = delete(conn, ~p"/api/v1/directories/contacts/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)["errors"]["id"] == "contact not found"
    end
  end
end
