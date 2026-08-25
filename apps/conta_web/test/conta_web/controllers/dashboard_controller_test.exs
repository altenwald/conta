defmodule ContaWeb.DashboardControllerTest do
  use ContaWeb.ConnCase, async: true

  setup :register_and_log_in_user

  describe "GET /dashboard/:type/:currency" do
    test "renders patrimony SVG image", %{conn: conn} do
      conn = get(conn, ~p"/dashboard/patrimony/EUR")
      assert response_content_type(conn, :svg)
      assert response(conn, 200)
      assert String.starts_with?(response(conn, 200), "<svg")
    end

    test "renders pnl SVG image", %{conn: conn} do
      conn = get(conn, ~p"/dashboard/pnl/EUR")
      assert response_content_type(conn, :svg)
      assert response(conn, 200)
      assert String.starts_with?(response(conn, 200), "<svg")
    end

    test "renders income SVG image", %{conn: conn} do
      conn = get(conn, ~p"/dashboard/income/EUR")
      assert response_content_type(conn, :svg)
      assert response(conn, 200)
      assert String.starts_with?(response(conn, 200), "<svg")
    end

    test "renders outcome SVG image", %{conn: conn} do
      conn = get(conn, ~p"/dashboard/outcome/EUR")
      assert response_content_type(conn, :svg)
      assert response(conn, 200)
      assert String.starts_with?(response(conn, 200), "<svg")
    end

    test "renders banks SVG image", %{conn: conn} do
      conn = get(conn, ~p"/dashboard/banks/EUR")
      assert response_content_type(conn, :svg)
      assert response(conn, 200)
      assert String.starts_with?(response(conn, 200), "<svg")
      assert response(conn, 200) =~ "prefers-color-scheme:dark"
    end

    test "renders dark theme SVG image when requested", %{conn: conn} do
      conn = get(conn, ~p"/dashboard/banks/EUR?theme=dark")
      assert response_content_type(conn, :svg)
      assert response(conn, 200)
      assert response(conn, 200) =~ "fill:#E5E7EB"
    end

    test "renders light theme SVG image when requested", %{conn: conn} do
      conn = get(conn, ~p"/dashboard/banks/EUR?theme=light")
      assert response_content_type(conn, :svg)
      assert response(conn, 200)
      assert response(conn, 200) =~ "fill:#374151"
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
