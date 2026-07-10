defmodule ContaWeb.FilterLiveTest do
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

    test "keeps existing params when clicking Add parameter as the first action on an edit page",
         %{conn: conn, user: user} do
      filter =
        insert(:filter, %{
          params: [
            build(:filter_param, %{name: "first", type: :string}),
            build(:filter_param, %{name: "second", type: :integer})
          ]
        })

      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/#{filter}/edit")

      html = form_live |> element("button", "Add parameter") |> render_click()

      assert html =~ ~s(value="first")
      assert html =~ ~s(value="second")
      # the newly added third, empty param
      assert html =~ ~s(name="set_filter[params][2][name]")
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

    test "shows a readable error instead of silently falling back to JSON when the Lua code is invalid", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/new")

      form_live
      |> form("#filter-form", set_filter: %{name: "broken filter", code: "return 1 +", output: "json"})
      |> render_change()

      html = form_live |> element("form[phx-submit=test_run]") |> render_submit()

      assert html =~ "Error"
      assert html =~ "syntax error"
      refute html =~ "null"
    end

    test "shows an error instead of silently returning null when the script has no return statement", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/new")

      form_live
      |> form("#filter-form", set_filter: %{name: "no return filter", code: "local x = 1", output: "json"})
      |> render_change()

      html = form_live |> element("form[phx-submit=test_run]") |> render_submit()

      assert html =~ "Error"
      assert html =~ "return"
      refute html =~ "null"
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

    test "loads a real data sample for a table param", %{conn: conn, user: user} do
      BookFixtures.insert(:invoice, %{invoice_number: "2023-00001"})
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/new")

      form_live
      |> form("#filter-form", set_filter: %{name: "invoice filter", output: "json"})
      |> render_change()

      form_live |> element("button", "Add parameter") |> render_click()

      form_live
      |> form("#filter-form", set_filter: %{params: %{"0" => %{"name" => "invoices", "type" => "table"}}})
      |> render_change()

      html = form_live |> element(~s(button[phx-click="load_table_sample"])) |> render_click()

      assert html =~ "2023-00001"
    end

    test "keeps a loaded real data sample after an unrelated form change", %{conn: conn, user: user} do
      BookFixtures.insert(:invoice, %{invoice_number: "2023-00001"})
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/new")

      form_live
      |> form("#filter-form", set_filter: %{name: "invoice filter", output: "json"})
      |> render_change()

      form_live |> element("button", "Add parameter") |> render_click()

      form_live
      |> form("#filter-form", set_filter: %{params: %{"0" => %{"name" => "invoices", "type" => "table"}}})
      |> render_change()

      html = form_live |> element(~s(button[phx-click="load_table_sample"])) |> render_click()
      assert html =~ "2023-00001"

      html =
        form_live
        |> form("#filter-form", set_filter: %{description: "updated"})
        |> render_change()

      assert html =~ "2023-00001"
    end

    test "restricts the parameter name to known table sources when type is table", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/new")

      form_live |> element("button", "Add parameter") |> render_click()

      html =
        form_live
        |> form("#filter-form", set_filter: %{params: %{"0" => %{"type" => "table"}}})
        |> render_change()

      assert html =~ ~s(<option value="expenses">Expenses</option>)
      assert html =~ ~s(<option value="invoices">Invoices</option>)
      assert html =~ "Sample size"
    end

    test "keeps the table select+sample-size UI when editing a sibling field on an already-saved table param",
         %{conn: conn, user: user} do
      filter =
        insert(:filter, %{
          params: [build(:filter_param, %{name: "expenses", type: :table, sample_limit: 5})]
        })

      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/#{filter}/edit")

      # Regression for an atom-vs-string bug: editing a *sibling* field
      # (sample_limit here) without touching the `type` select itself must not
      # flip `p[:type].value` back to a raw string that fails an atom comparison
      # and silently reverts the row to the free-text Name/Options layout.
      html =
        form_live
        |> form("#filter-form", set_filter: %{params: %{"0" => %{"sample_limit" => "8"}}})
        |> render_change()

      # "expenses" is already the persisted value here, so Phoenix.HTML's
      # options_for_select/2 marks it with a `selected` attribute inserted
      # before `value=`; match the stable tail instead of the full literal tag.
      assert html =~ ~s(value="expenses">Expenses</option>)
      assert html =~ ~s(<option value="invoices">Invoices</option>)
      assert html =~ "Sample size"
    end

    test "does not crash Load real data when sample_limit is set to a non-positive value",
         %{conn: conn, user: user} do
      BookFixtures.insert(:invoice, %{invoice_number: "2023-00001"})
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/new")

      form_live
      |> form("#filter-form", set_filter: %{name: "invoice filter", output: "json"})
      |> render_change()

      form_live |> element("button", "Add parameter") |> render_click()

      form_live
      |> form("#filter-form", set_filter: %{params: %{"0" => %{"name" => "invoices", "type" => "table"}}})
      |> render_change()

      form_live
      |> form("#filter-form", set_filter: %{params: %{"0" => %{"sample_limit" => "-1"}}})
      |> render_change()

      html = form_live |> element(~s(button[phx-click="load_table_sample"])) |> render_click()

      assert Process.alive?(form_live.pid)
      assert html =~ "2023-00001"
    end

    test "keeps the persisted name of a table param that is not in the known table sources",
         %{conn: conn, user: user} do
      filter =
        insert(:filter, %{
          params: [build(:filter_param, %{name: "custom_data", type: :table, sample_limit: 5})]
        })

      conn = log_in_user(conn, user)
      {:ok, form_live, html} = live(conn, ~p"/automation/filters/#{filter}/edit")

      # "custom_data" is already the persisted value here, so Phoenix.HTML's
      # options_for_select/2 marks it with a `selected` attribute inserted
      # before `value=`; match the stable tail instead of the full literal tag.
      assert html =~ ~s(value="custom_data">custom_data</option>)
      assert html =~ ~s(<option value="expenses">Expenses</option>)
      assert html =~ ~s(<option value="invoices">Invoices</option>)

      result =
        form_live
        |> form("#filter-form", set_filter: %{description: "updated description"})
        |> render_submit()

      wait_for_event(Conta.Commanded.Application, Conta.Event.FilterSet)

      {:ok, _index_live, _html} = follow_redirect(result, conn, ~p"/automation/filters")

      updated_filter = Automator.get_filter(filter.id)
      assert Enum.any?(updated_filter.params, &(&1.name == "custom_data"))
    end

    test "shows Options only for type options, joined with commas", %{conn: conn, user: user} do
      filter =
        insert(:filter, %{
          params: [build(:filter_param, %{name: "choice", type: :options, options: ["a", "b", "c"]})]
        })

      conn = log_in_user(conn, user)
      {:ok, form_live, html} = live(conn, ~p"/automation/filters/#{filter}/edit")

      assert html =~ "Options (comma separated)"
      assert html =~ ~s(value="a, b, c")

      # The changeset normalizes this field back into a list on every
      # phx-change; a sibling field changing must not corrupt the joined text.
      html =
        form_live
        |> form("#filter-form", set_filter: %{description: "updated"})
        |> render_change()

      assert html =~ ~s(value="a, b, c")
    end

    test "hides Options for non-options, non-table param types", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/new")

      form_live |> element("button", "Add parameter") |> render_click()

      html =
        form_live
        |> form("#filter-form", set_filter: %{params: %{"0" => %{"type" => "string"}}})
        |> render_change()

      refute html =~ "Options (comma separated)"
    end
  end
end
