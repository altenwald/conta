defmodule ContaWeb.DashboardControllerTest do
  use ContaWeb.ConnCase, async: true

  setup :register_and_log_in_user

  describe "GET /dashboard/:type/:currency" do
    test "renders patrimony PNG image", %{conn: conn} do
      conn = get(conn, ~p"/dashboard/patrimony/EUR")
      assert response_content_type(conn, :png)
      assert response(conn, 200)
      assert binary_part(response(conn, 200), 0, 8) == <<137, 80, 78, 71, 13, 10, 26, 10>>
    end

    test "renders pnl PNG image", %{conn: conn} do
      conn = get(conn, ~p"/dashboard/pnl/EUR")
      assert response_content_type(conn, :png)
      assert response(conn, 200)
      assert binary_part(response(conn, 200), 0, 8) == <<137, 80, 78, 71, 13, 10, 26, 10>>
    end

    test "renders income PNG image", %{conn: conn} do
      conn = get(conn, ~p"/dashboard/income/EUR")
      assert response_content_type(conn, :png)
      assert response(conn, 200)
      assert binary_part(response(conn, 200), 0, 8) == <<137, 80, 78, 71, 13, 10, 26, 10>>
    end

    test "renders outcome PNG image", %{conn: conn} do
      conn = get(conn, ~p"/dashboard/outcome/EUR")
      assert response_content_type(conn, :png)
      assert response(conn, 200)
      assert binary_part(response(conn, 200), 0, 8) == <<137, 80, 78, 71, 13, 10, 26, 10>>
    end

    test "returns 404 for invalid type", %{conn: conn} do
      conn = get(conn, ~p"/dashboard/invalid/EUR")
      assert response(conn, 404)
    end

    test "returns 404 for invalid currency", %{conn: conn} do
      conn = get(conn, ~p"/dashboard/patrimony/INVALID")
      assert response(conn, 404)
    end
  end
end
