defmodule ContaWeb.ReconciliationLive.MatchesTest do
  use ContaWeb.ConnCase

  import Commanded.Assertions.EventAssertions
  import Phoenix.LiveViewTest
  import Conta.ReconciliationFixtures
  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.AccountsFixtures
  alias Conta.Command.SetAccount
  alias Conta.Command.SetMatchRule
  alias Conta.Projector.Reconciliation.MatchRule
  alias Conta.Reconciliation
  alias Conta.Repo

  setup do
    user = AccountsFixtures.insert(:user) |> AccountsFixtures.confirm_user()

    :ok = dispatch(%SetAccount{name: ["Expenses"], type: :expenses, currency: :EUR, ledger: "default"})

    :ok =
      dispatch(%SetAccount{name: ["Expenses", "Misc"], type: :expenses, currency: :EUR, ledger: "default"})

    :ok =
      dispatch(%SetAccount{
        name: ["Expenses", "Subscriptions"],
        type: :expenses,
        currency: :EUR,
        ledger: "default"
      })

    %{user: user}
  end

  # `SetMatchRule` only accepts a pre-set `:id` when the aggregate already knows
  # that id (see `Conta.Aggregate.Reconciliation.execute/2` - a non-nil id that
  # isn't in `match_rules` yet is rejected with `{:error, %{id: ["not found"]}}`,
  # unlike Shortcut/Importer, which key off `name` and accept any id). So, unlike
  # `ShortcutLiveTest`'s "seed the aggregate from a read-model-only fixture"
  # pattern, a match rule usable by both the aggregate and the read model has to
  # be created through a real `SetMatchRule` dispatch (id: nil) and then read back
  # from the projected list (via `eventually/1`, see below) to learn its
  # server-generated id.
  defp create_match_rule(attrs) do
    command = %SetMatchRule{
      name: attrs[:name] || "rule #{System.unique_integer([:positive])}",
      conditions: [%SetMatchRule.Condition{field: :description, comparator: :contains, value: "X"}],
      match_type: :all,
      account_name: attrs[:account_name] || ["Expenses", "Misc"]
    }

    :ok = dispatch(command)

    wait_for_event(Conta.Commanded.Application, Conta.Event.MatchRuleSet, fn event ->
      event.name == command.name
    end)

    eventually(fn -> Repo.get_by(MatchRule, name: command.name) end)
  end

  describe "Index" do
    test "lists all match rules", %{conn: conn, user: user} do
      _rule = insert(:match_rule, name: "my rule")
      conn = log_in_user(conn, user)

      {:ok, _index_live, html} = live(conn, ~p"/ledger/reconciliation/matches")

      assert html =~ "my rule"
    end

    test "deletes a match rule in listing", %{conn: conn, user: user} do
      rule = create_match_rule(name: "to be removed")
      conn = log_in_user(conn, user)

      {:ok, index_live, _html} = live(conn, ~p"/ledger/reconciliation/matches")

      assert index_live
             |> element("#match_rules-#{rule.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#match_rules-#{rule.id}")

      # Let the async projector's delete land before the test's sandboxed
      # connection tears down (see the identical rationale in `upload_test.exs`
      # for why an un-awaited async write here can crash later tests).
      assert eventually(fn -> is_nil(Repo.get(MatchRule, rule.id)) end)
    end

    test "reorders match rules with move up/move down buttons", %{conn: conn, user: user} do
      rule_a = create_match_rule(name: "rule A")
      rule_b = create_match_rule(name: "rule B")
      conn = log_in_user(conn, user)

      {:ok, index_live, html} = live(conn, ~p"/ledger/reconciliation/matches")
      assert index_of(html, "rule A") < index_of(html, "rule B")

      html =
        index_live
        |> element("#match_rules-#{rule_b.id} a[phx-click=move_up]")
        |> render_click()

      assert index_of(html, "rule B") < index_of(html, "rule A")

      html =
        index_live
        |> element("#match_rules-#{rule_b.id} a[phx-click=move_down]")
        |> render_click()

      assert index_of(html, "rule A") < index_of(html, "rule B")

      # Let the async projector's position updates land before the test's
      # sandboxed connection tears down (see the identical rationale in
      # `upload_test.exs`).
      rule_a_id = rule_a.id
      rule_b_id = rule_b.id

      assert eventually(fn ->
               match?([%{id: ^rule_a_id}, %{id: ^rule_b_id}], Reconciliation.list_match_rules())
             end)
    end
  end

  describe "Form" do
    test "creates a new match rule with one condition", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/ledger/reconciliation/matches/new")

      form_live |> element("button", "Add condition") |> render_click()

      result =
        form_live
        |> form("#match-rule-form",
          set_match_rule: %{
            name: "Netflix",
            match_type: "all",
            account_name: "Expenses.Subscriptions",
            conditions: %{
              "0" => %{"field" => "description", "comparator" => "contains", "value" => "NETFLIX"}
            }
          }
        )
        |> render_submit()

      wait_for_event(Conta.Commanded.Application, Conta.Event.MatchRuleSet, fn event ->
        event.name == "Netflix"
      end)

      assert eventually(fn -> Repo.get_by(MatchRule, name: "Netflix") end)

      {:ok, _index_live, html} = follow_redirect(result, conn, ~p"/ledger/reconciliation/matches")

      assert html =~ "Match rule saved successfully"
      assert html =~ "Netflix"
    end

    test "edits an existing match rule", %{conn: conn, user: user} do
      rule = create_match_rule(name: "old name")
      conn = log_in_user(conn, user)

      {:ok, form_live, _html} = live(conn, ~p"/ledger/reconciliation/matches/#{rule}/edit")

      result =
        form_live
        |> form("#match-rule-form", set_match_rule: %{name: "new name"})
        |> render_submit()

      wait_for_event(Conta.Commanded.Application, Conta.Event.MatchRuleSet, fn event ->
        event.name == "new name"
      end)

      assert eventually(fn -> Repo.get_by(MatchRule, name: "new name") end)

      {:ok, _index_live, html} = follow_redirect(result, conn, ~p"/ledger/reconciliation/matches")

      assert html =~ "Match rule saved successfully"
      assert html =~ "new name"
    end
  end

  defp index_of(html, text) do
    {index, _length} = :binary.match(html, text)
    index
  end

  defp eventually(fun, attempts \\ 100)

  defp eventually(fun, attempts) when attempts > 1 do
    fun.() ||
      (
        Process.sleep(10)
        eventually(fun, attempts - 1)
      )
  end

  defp eventually(fun, _attempts), do: fun.()
end
