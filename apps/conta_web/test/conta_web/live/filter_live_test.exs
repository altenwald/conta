defmodule ContaWeb.FilterLiveTest do
  use ContaWeb.ConnCase

  import Commanded.Assertions.EventAssertions
  import Phoenix.LiveViewTest
  import Conta.AutomatorFixtures
  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Automator
  alias Conta.AccountsFixtures

  setup do
    user = AccountsFixtures.insert(:user) |> AccountsFixtures.confirm_user()
    %{user: user}
  end

  describe "Index" do
    test "lists all filters", %{conn: conn, user: user} do
      _filter = insert(:filter, %{name: "my filter"})
      conn = log_in_user(conn, user)

      {:ok, _index_live, html} = live(conn, ~p"/automation/filters")

      assert html =~ "my filter"
    end

    test "deletes filter in listing", %{conn: conn, user: user} do
      filter = insert(:filter, %{name: "to be removed"})
      # The filter fixture only writes to the read model. The RemoveFilter
      # command validates against the event-sourced aggregate, so the
      # aggregate needs to know about this filter first (this updates the
      # same projected row, since the projector matches by name+automator).
      :ok = dispatch(Automator.get_set_filter(filter))
      conn = log_in_user(conn, user)

      {:ok, index_live, _html} = live(conn, ~p"/automation/filters")

      assert index_live
             |> element("#automator_filters-#{filter.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#automator_filters-#{filter.id}")
    end
  end

  describe "Form" do
    test "creates a new filter", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/new")

      assert form_live
             |> form("#filter-form", set_filter: %{name: "", output: "json"})
             |> render_change() =~ "can&#39;t be blank"

      result =
        form_live
        |> form("#filter-form", set_filter: %{name: "brand new filter", output: "json"})
        |> render_submit()

      wait_for_event(Conta.Commanded.Application, Conta.Event.FilterSet)

      {:ok, _index_live, html} = follow_redirect(result, conn, ~p"/automation/filters")

      assert html =~ "Filter saved successfully"
      assert html =~ "brand new filter"
    end

    test "edits an existing filter", %{conn: conn, user: user} do
      filter = insert(:filter, %{name: "old name"})
      conn = log_in_user(conn, user)

      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/#{filter}/edit")

      result =
        form_live
        |> form("#filter-form", set_filter: %{name: "new name"})
        |> render_submit()

      wait_for_event(Conta.Commanded.Application, Conta.Event.FilterSet)

      {:ok, _index_live, html} = follow_redirect(result, conn, ~p"/automation/filters")

      assert html =~ "Filter saved successfully"
      assert html =~ "new name"
    end

    test "test-runs the Lua code without dispatching anything", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/new")

      form_live
      |> form("#filter-form", set_filter: %{name: "sum filter", code: "return 1 + 1", output: "json"})
      |> render_change()

      html = form_live |> element("form[phx-submit=test_run]") |> render_submit()

      assert html =~ "2"
    end

    test "shows an HTML table when output is xlsx and the script returns row data", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/new")

      code = ~S"""
      return {{name = "Alice", amount = 100}, {name = "Bob", amount = 200}}
      """

      form_live
      |> form("#filter-form", set_filter: %{name: "table filter", code: code, output: "xlsx"})
      |> render_change()

      html = form_live |> element("form[phx-submit=test_run]") |> render_submit()

      assert html =~ "<table"
      assert html =~ "Alice"
      assert html =~ "Bob"
      assert html =~ "amount"
    end

    test "falls back to raw JSON when output is xlsx but the result has no table shape", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/new")

      form_live
      |> form("#filter-form", set_filter: %{name: "scalar filter", code: "return 42", output: "xlsx"})
      |> render_change()

      html = form_live |> element("form[phx-submit=test_run]") |> render_submit()

      refute html =~ "<table"
      assert html =~ "42"
      assert html =~ "table shape"
    end

    test "renders a placeholder instead of crashing when a cell is a nested table", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/new")

      code = ~S"""
      return {{name = "Alice", meta = {a = 1}}}
      """

      form_live
      |> form("#filter-form", set_filter: %{name: "nested cell filter", code: code, output: "xlsx"})
      |> render_change()

      html = form_live |> element("form[phx-submit=test_run]") |> render_submit()

      assert html =~ "<table"
      assert html =~ "Alice"
      assert html =~ "cannot convert"
    end
  end
end
