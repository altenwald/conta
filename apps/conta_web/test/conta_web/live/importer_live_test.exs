defmodule ContaWeb.ImporterLiveTest do
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
    test "lists all importers", %{conn: conn, user: user} do
      _importer = insert(:importer, %{name: "my importer"})
      conn = log_in_user(conn, user)

      {:ok, _index_live, html} = live(conn, ~p"/automation/importers")

      assert html =~ "my importer"
    end

    test "deletes importer in listing", %{conn: conn, user: user} do
      importer = insert(:importer, %{name: "to be removed"})
      # The importer fixture only writes to the read model. The RemoveImporter
      # command validates against the event-sourced aggregate, so the
      # aggregate needs to know about this importer first (this updates the
      # same projected row, since the projector matches by name+automator).
      :ok = dispatch(Automator.get_set_importer(importer))
      conn = log_in_user(conn, user)

      {:ok, index_live, _html} = live(conn, ~p"/automation/importers")

      assert index_live
             |> element("#automator_importers-#{importer.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#automator_importers-#{importer.id}")
    end

    test "shows an importer created after the initial mount, via the projector's broadcast", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, index_live, html} = live(conn, ~p"/automation/importers")
      refute html =~ "late arriving importer"

      # Simulates the projector finishing its write *after* this index already
      # mounted and queried - the same race the Form's `push_navigate` can lose
      # against `Conta.Projector.Automator` in production (command dispatch
      # defaults to `consistency: :eventual`). The index must pick this up from
      # the broadcast alone, not by re-querying.
      late_importer = insert(:importer, %{name: "late arriving importer"})
      send(index_live.pid, {:importer_set, late_importer})

      assert render(index_live) =~ "late arriving importer"
    end
  end

  describe "Form" do
    test "creates a new importer", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/importers/new")

      assert form_live
             |> form("#importer-form", set_importer: %{name: ""})
             |> render_change() =~ "can&#39;t be blank"

      result =
        form_live
        |> form("#importer-form", set_importer: %{name: "brand new importer"})
        |> render_submit()

      wait_for_event(Conta.Commanded.Application, Conta.Event.ImporterSet)

      {:ok, _index_live, html} = follow_redirect(result, conn, ~p"/automation/importers")

      assert html =~ "Importer saved successfully"
      assert html =~ "brand new importer"
    end

    test "edits an existing importer", %{conn: conn, user: user} do
      importer = insert(:importer, %{name: "old name"})
      conn = log_in_user(conn, user)

      {:ok, form_live, _html} = live(conn, ~p"/automation/importers/#{importer}/edit")

      result =
        form_live
        |> form("#importer-form", set_importer: %{name: "new name"})
        |> render_submit()

      wait_for_event(Conta.Commanded.Application, Conta.Event.ImporterSet)

      {:ok, _index_live, html} = follow_redirect(result, conn, ~p"/automation/importers")

      assert html =~ "Importer saved successfully"
      assert html =~ "new name"
    end

    test "test-runs the Lua code and shows the commands without dispatching them", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/importers/new")

      code = ~S[return {status = "ok", commands = {{type = "movement", data = {foo = "bar"}}}}]

      form_live
      |> form("#importer-form", set_importer: %{name: "gen commands", code: code})
      |> render_change()

      html = form_live |> element("form[phx-submit=test_run]") |> render_submit()

      assert html =~ "movement"
      assert html =~ "foo"
    end

    test "test-runs the fixed movements table param's CSV test data through the script", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/importers/new")

      code = ~S"""
      local total = 0
      for _, row in ipairs(movements) do
        total = total + tonumber(row.amount)
      end
      return {status = "ok", commands = {{type = "total", data = {total = total}}}}
      """

      form_live
      |> form("#importer-form", set_importer: %{name: "sum rows", code: code})
      |> render_change()

      csv = "amount\n10\n5\n"

      html =
        form_live
        |> element("form[phx-submit=test_run]")
        |> render_submit(%{"test_params" => %{"movements" => csv}})

      assert html =~ "total"
      assert html =~ "15"
    end

    test "keeps the submitted movements CSV in the textarea after running", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/importers/new")

      code = ~S[return {status = "ok", commands = {}}]

      form_live
      |> form("#importer-form", set_importer: %{name: "sum rows", code: code})
      |> render_change()

      csv = "amount\n10\n5\n"

      html =
        form_live
        |> element("form[phx-submit=test_run]")
        |> render_submit(%{"test_params" => %{"movements" => csv}})

      assert html =~ "amount\n10\n5"
    end

    test "shows a column-mismatch error for malformed CSV test data", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/importers/new")

      code = ~S[return {status = "ok", commands = {}}]

      form_live
      |> form("#importer-form", set_importer: %{name: "malformed csv", code: code})
      |> render_change()

      csv = "date,amount\n2026-07-01\n"

      html =
        form_live
        |> element("form[phx-submit=test_run]")
        |> render_submit(%{"test_params" => %{"movements" => csv}})

      assert html =~ "Row 2 has a different number of columns than the header"
    end

    test "treats blank movements test data as an empty table, not an error", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/importers/new")

      code = ~S"""
      local count = 0
      for _ in ipairs(movements) do count = count + 1 end
      return {status = "ok", commands = {{type = "count", data = {count = count}}}}
      """

      form_live
      |> form("#importer-form", set_importer: %{name: "count rows", code: code})
      |> render_change()

      html =
        form_live
        |> element("form[phx-submit=test_run]")
        |> render_submit(%{"test_params" => %{"movements" => ""}})

      refute html =~ "Error"
      assert html =~ "count"
    end
  end
end
