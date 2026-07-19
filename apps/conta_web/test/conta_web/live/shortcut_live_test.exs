defmodule ContaWeb.ShortcutLiveTest do
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
    test "lists all shortcuts", %{conn: conn, user: user} do
      _shortcut = insert(:shortcut, %{name: "my shortcut"})
      conn = log_in_user(conn, user)

      {:ok, _index_live, html} = live(conn, ~p"/automation/shortcuts")

      assert html =~ "my shortcut"
    end

    test "deletes shortcut in listing", %{conn: conn, user: user} do
      shortcut = insert(:shortcut, %{name: "to be removed"})
      # The shortcut fixture only writes to the read model. The RemoveShortcut
      # command validates against the event-sourced aggregate, so the
      # aggregate needs to know about this shortcut first (this updates the
      # same projected row, since the projector matches by name+automator).
      :ok = dispatch(Automator.get_set_shortcut(shortcut))
      conn = log_in_user(conn, user)

      {:ok, index_live, _html} = live(conn, ~p"/automation/shortcuts")

      assert index_live
             |> element("#automator_shortcuts-#{shortcut.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#automator_shortcuts-#{shortcut.id}")
    end

    test "shows a shortcut created after the initial mount, via the projector's broadcast", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, index_live, html} = live(conn, ~p"/automation/shortcuts")
      refute html =~ "late arriving shortcut"

      late_shortcut = insert(:shortcut, %{name: "late arriving shortcut"})
      send(index_live.pid, {:shortcut_set, late_shortcut})

      assert render(index_live) =~ "late arriving shortcut"
    end
  end

  describe "Form" do
    test "creates a new shortcut", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/shortcuts/new")

      assert form_live
             |> form("#shortcut-form", set_shortcut: %{name: ""})
             |> render_change() =~ "can&#39;t be blank"

      result =
        form_live
        |> form("#shortcut-form", set_shortcut: %{name: "brand new shortcut"})
        |> render_submit()

      wait_for_event(Conta.Commanded.Application, Conta.Event.ShortcutSet)

      {:ok, _index_live, html} = follow_redirect(result, conn, ~p"/automation/shortcuts")

      assert html =~ "Shortcut saved successfully"
      assert html =~ "brand new shortcut"
    end

    test "edits an existing shortcut", %{conn: conn, user: user} do
      shortcut = insert(:shortcut, %{name: "old name"})
      conn = log_in_user(conn, user)

      {:ok, form_live, _html} = live(conn, ~p"/automation/shortcuts/#{shortcut}/edit")

      result =
        form_live
        |> form("#shortcut-form", set_shortcut: %{name: "new name"})
        |> render_submit()

      wait_for_event(Conta.Commanded.Application, Conta.Event.ShortcutSet)

      {:ok, _index_live, html} = follow_redirect(result, conn, ~p"/automation/shortcuts")

      assert html =~ "Shortcut saved successfully"
      assert html =~ "new name"
    end

    test "keeps existing params when clicking Add parameter as the first action on an edit page",
         %{conn: conn, user: user} do
      shortcut =
        insert(:shortcut, %{
          params: [
            build(:shortcut_param, %{name: "first", type: :string}),
            build(:shortcut_param, %{name: "second", type: :integer})
          ]
        })

      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/shortcuts/#{shortcut}/edit")

      html = form_live |> element("button", "Add parameter") |> render_click()

      assert html =~ ~s(value="first")
      assert html =~ ~s(value="second")
      # the newly added third, empty param
      assert html =~ ~s(name="set_shortcut[params][2][name]")
    end

    test "test-runs the Lua code and shows the commands without dispatching them", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/shortcuts/new")

      code = ~S[return {status = "ok", commands = {{type = "transaction", data = {foo = "bar"}}}}]

      form_live
      |> form("#shortcut-form", set_shortcut: %{name: "gen commands", code: code})
      |> render_change()

      html = form_live |> element("form[phx-submit=test_run]") |> render_submit()

      assert html =~ "transaction"
      assert html =~ "foo"
    end

    test "table params use a plain free-text Name field, not a table-sources dropdown", %{conn: conn, user: user} do
      # Unlike Filters, a Shortcut's :table param isn't a reference to one of
      # the app's registered TableSources - it's arbitrary JSON tabular data
      # the caller provides for the script to transform. The param editor
      # must not restrict/rewrite its name, offer a table-sources dropdown, a
      # sample-size field, or a "Load real data" button.
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/shortcuts/new")

      form_live |> element("button", "Add parameter") |> render_click()

      html =
        form_live
        |> form("#shortcut-form", set_shortcut: %{params: %{"0" => %{"name" => "any_name", "type" => "table"}}})
        |> render_change()

      refute html =~ ~s(<option value="expenses">Expenses</option>)
      refute html =~ ~s(<option value="invoices">Invoices</option>)
      refute html =~ "Sample size"
      refute html =~ "Load real data"
      assert html =~ ~s(value="any_name")
    end

    test "test-runs a table param's raw JSON test data through the script", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/shortcuts/new")

      form_live |> element("button", "Add parameter") |> render_click()

      code = ~S"""
      local total = 0
      for _, row in ipairs(rows) do
        total = total + row.amount
      end
      return {status = "ok", commands = {{type = "total", data = {total = total}}}}
      """

      form_live
      |> form("#shortcut-form",
        set_shortcut: %{name: "sum rows", code: code, params: %{"0" => %{"name" => "rows", "type" => "table"}}}
      )
      |> render_change()

      html =
        form_live
        |> element("form[phx-submit=test_run]")
        |> render_submit(%{"test_params" => %{"rows" => ~S([{"amount": 10}, {"amount": 5}])}})

      assert html =~ "total"
      assert html =~ "15"
    end

    test "shows Options only for type options, joined with commas", %{conn: conn, user: user} do
      shortcut =
        insert(:shortcut, %{
          params: [build(:shortcut_param, %{name: "choice", type: :options, options: ["a", "b", "c"]})]
        })

      conn = log_in_user(conn, user)
      {:ok, form_live, html} = live(conn, ~p"/automation/shortcuts/#{shortcut}/edit")

      assert html =~ "Options (comma separated)"
      assert html =~ ~s(value="a, b, c")

      # The changeset normalizes this field back into a list on every
      # phx-change; a sibling field changing must not corrupt the joined text.
      html =
        form_live
        |> form("#shortcut-form", set_shortcut: %{description: "updated"})
        |> render_change()

      assert html =~ ~s(value="a, b, c")
    end

    test "hides Options for non-options param types", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/shortcuts/new")

      form_live |> element("button", "Add parameter") |> render_click()

      html =
        form_live
        |> form("#shortcut-form", set_shortcut: %{params: %{"0" => %{"type" => "string"}}})
        |> render_change()

      refute html =~ "Options (comma separated)"
    end
  end
end
