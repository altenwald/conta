defmodule ContaWeb.ShortcutLiveTest do
  use ContaWeb.ConnCase

  import Commanded.Assertions.EventAssertions
  import Phoenix.LiveViewTest
  import Conta.AutomatorFixtures
  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Automator
  alias Conta.AccountsFixtures
  alias Conta.BookFixtures

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

    test "loads a real data sample for a table param", %{conn: conn, user: user} do
      BookFixtures.insert(:invoice, %{invoice_number: "2023-00001"})
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/shortcuts/new")

      form_live
      |> form("#shortcut-form", set_shortcut: %{name: "invoice shortcut"})
      |> render_change()

      form_live |> element("button", "Add parameter") |> render_click()

      form_live
      |> form("#shortcut-form", set_shortcut: %{params: %{"0" => %{"name" => "invoices", "type" => "table"}}})
      |> render_change()

      html = form_live |> element(~s(button[phx-click="load_table_sample"])) |> render_click()

      assert html =~ "2023-00001"
    end

    test "keeps a loaded real data sample after an unrelated form change", %{conn: conn, user: user} do
      BookFixtures.insert(:invoice, %{invoice_number: "2023-00001"})
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/shortcuts/new")

      form_live
      |> form("#shortcut-form", set_shortcut: %{name: "invoice shortcut"})
      |> render_change()

      form_live |> element("button", "Add parameter") |> render_click()

      form_live
      |> form("#shortcut-form", set_shortcut: %{params: %{"0" => %{"name" => "invoices", "type" => "table"}}})
      |> render_change()

      html = form_live |> element(~s(button[phx-click="load_table_sample"])) |> render_click()
      assert html =~ "2023-00001"

      html =
        form_live
        |> form("#shortcut-form", set_shortcut: %{description: "updated"})
        |> render_change()

      assert html =~ "2023-00001"
    end

    test "restricts the parameter name to known table sources when type is table", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/shortcuts/new")

      form_live |> element("button", "Add parameter") |> render_click()

      html =
        form_live
        |> form("#shortcut-form", set_shortcut: %{params: %{"0" => %{"type" => "table"}}})
        |> render_change()

      assert html =~ ~s(<option value="expenses">Expenses</option>)
      assert html =~ ~s(<option value="invoices">Invoices</option>)
      assert html =~ "Sample size"
    end

    test "keeps the table select+sample-size UI when editing a sibling field on an already-saved table param",
         %{conn: conn, user: user} do
      shortcut =
        insert(:shortcut, %{
          params: [build(:shortcut_param, %{name: "expenses", type: :table, sample_limit: 5})]
        })

      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/shortcuts/#{shortcut}/edit")

      # Regression for an atom-vs-string bug: editing a *sibling* field
      # (sample_limit here) without touching the `type` select itself must not
      # flip `p[:type].value` back to a raw string that fails an atom comparison
      # and silently reverts the row to the free-text Name/Options layout.
      html =
        form_live
        |> form("#shortcut-form", set_shortcut: %{params: %{"0" => %{"sample_limit" => "8"}}})
        |> render_change()

      # "expenses" is already the persisted value here, so Phoenix.HTML's
      # options_for_select/2 marks it with a `selected` attribute inserted
      # before `value=`; match the stable tail instead of the full literal tag.
      assert html =~ ~s(value="expenses">Expenses</option>)
      assert html =~ ~s(<option value="invoices">Invoices</option>)
      assert html =~ "Sample size"
    end
  end
end
