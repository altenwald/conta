defmodule ContaWeb.DashboardLiveTest do
  use ContaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders dashboard with all 5 chart cards including Banks", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/dashboard")

    assert html =~ "Dashboard"
    assert html =~ "Banks"
    assert html =~ "Outcome"
    assert html =~ "Income"
    assert html =~ "Profits and Loses"
    assert has_element?(view, ".chart-container svg")
    assert html =~ "<svg"
  end
end
