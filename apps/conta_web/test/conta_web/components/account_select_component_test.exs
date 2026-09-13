defmodule ContaWeb.AccountSelectComponentTest do
  use ContaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias ContaWeb.AccountSelectComponent

  defmodule HostLive do
    use ContaWeb, :live_view

    def mount(_params, session, socket) do
      {:ok,
       Phoenix.Component.assign(socket,
         current_user: session["user"],
         selected: nil,
         accounts: [
           "Assets.Bank.BBVA",
           "Assets.Bank.Caixa",
           "Expenses.Office.Supplies",
           "Expenses.Utilities.Electricity",
           "Liabilities.Loan.BBVA"
         ]
       ), layout: false}
    end

    def render(assigns) do
      ~H"""
      <div id="host-root">
        <.live_component
          module={AccountSelectComponent}
          id="test-selector"
          value={@selected}
          accounts={@accounts}
        />
        <div id="selected-result">{@selected}</div>
      </div>
      """
    end

    def handle_info({:account_selected, _id, value}, socket) do
      {:noreply, Phoenix.Component.assign(socket, :selected, value)}
    end
  end

  describe "filter_accounts/3 logic" do
    setup do
      accounts = [
        "Assets.Bank.BBVA",
        "Assets.Bank.Caixa",
        "Expenses.Office.Supplies",
        "Expenses.Utilities.Electricity",
        "Liabilities.Loan.BBVA"
      ]

      %{accounts: accounts}
    end

    test "returns top N accounts when query is nil or empty", %{accounts: accounts} do
      assert AccountSelectComponent.filter_accounts(accounts, nil, 3) == [
               "Assets.Bank.BBVA",
               "Assets.Bank.Caixa",
               "Expenses.Office.Supplies"
             ]

      assert AccountSelectComponent.filter_accounts(accounts, "", 2) == [
               "Assets.Bank.BBVA",
               "Assets.Bank.Caixa"
             ]
    end

    test "matches accounts by arbitrary substring (not just prefix)", %{accounts: accounts} do
      # "bbva" appears in Assets.Bank.BBVA and Liabilities.Loan.BBVA
      bbva_matches = AccountSelectComponent.filter_accounts(accounts, "bbva")
      assert length(bbva_matches) == 2
      assert "Assets.Bank.BBVA" in bbva_matches
      assert "Liabilities.Loan.BBVA" in bbva_matches

      # "electr" appears in Expenses.Utilities.Electricity
      elec_matches = AccountSelectComponent.filter_accounts(accounts, "electr")
      assert elec_matches == ["Expenses.Utilities.Electricity"]
    end

    test "case-insensitive search", %{accounts: accounts} do
      assert AccountSelectComponent.filter_accounts(accounts, "SUPPLIES") == [
               "Expenses.Office.Supplies"
             ]
    end

    test "smart ranking prioritizes exact and segment matches", %{accounts: accounts} do
      results = AccountSelectComponent.filter_accounts(accounts, "bank")
      # Both "Assets.Bank.BBVA" and "Assets.Bank.Caixa" have segment ".Bank"
      assert Enum.all?(results, &String.contains?(&1, "Bank"))
    end
  end

  describe "AccountSelectComponent in LiveView" do
    setup :register_and_log_in_user

    test "in resting state, dropdown is not rendered in the DOM", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, HostLive)

      assert has_element?(view, "#test-selector input")
      refute has_element?(view, "#test-selector [role=listbox]")
      refute has_element?(view, "#test-selector button[role=option]")
    end

    test "focusing input opens on-demand dropdown with accounts", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, HostLive)

      view
      |> element("#test-selector-input")
      |> render_focus()

      assert has_element?(view, "#test-selector [role=listbox]")
      assert has_element?(view, "#test-selector button[role=option]", "Assets.Bank.BBVA")
    end

    test "typing filters accounts by substring", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, HostLive)

      view
      |> element("#test-selector-input")
      |> render_keyup(%{"query" => "bbva"})

      assert has_element?(view, "#test-selector button[role=option]", "Assets.Bank.BBVA")
      assert has_element?(view, "#test-selector button[role=option]", "Liabilities.Loan.BBVA")
      refute has_element?(view, "#test-selector button[role=option]", "Expenses.Office.Supplies")
    end

    test "selecting an account updates value, notifies parent, and clears dropdown from DOM", %{
      conn: conn
    } do
      {:ok, view, _html} = live_isolated(conn, HostLive)

      view
      |> element("#test-selector-input")
      |> render_keyup(%{"query" => "elec"})

      # Click the matching option
      view
      |> element("#test-selector button[role=option]", "Expenses.Utilities.Electricity")
      |> render_click()

      # Dropdown should be immediately purged from the DOM
      refute has_element?(view, "#test-selector [role=listbox]")
      refute has_element?(view, "#test-selector button[role=option]")

      # Parent LiveView received the update
      assert has_element?(view, "#selected-result", "Expenses.Utilities.Electricity")
    end

    test "Escape key closes the dropdown and clears options from DOM", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, HostLive)

      view
      |> element("#test-selector-input")
      |> render_focus()

      assert has_element?(view, "#test-selector [role=listbox]")

      view
      |> element("#test-selector-input")
      |> render_keydown(%{"key" => "Escape"})

      refute has_element?(view, "#test-selector [role=listbox]")
    end

    test "click-away event closes the dropdown", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, HostLive)

      view
      |> element("#test-selector-input")
      |> render_focus()

      assert has_element?(view, "#test-selector [role=listbox]")

      # Click backdrop to close
      view
      |> element("#test-selector-backdrop")
      |> render_click()

      refute has_element?(view, "#test-selector [role=listbox]")
      refute has_element?(view, "#test-selector-backdrop")
    end
  end
end
