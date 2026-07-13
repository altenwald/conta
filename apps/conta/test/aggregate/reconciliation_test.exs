defmodule Conta.Aggregate.ReconciliationTest do
  use ExUnit.Case

  alias Conta.Aggregate.Reconciliation

  alias Conta.Command.RemoveMatchRule
  alias Conta.Command.ReorderMatchRules
  alias Conta.Command.SetMatchRule

  alias Conta.Event.MatchRuleRemoved
  alias Conta.Event.MatchRuleSet
  alias Conta.Event.MatchRulesReordered

  describe "match rules" do
    test "create a new rule successfully" do
      reconciliation = %Reconciliation{}

      command = %SetMatchRule{
        name: "Netflix",
        conditions: [%SetMatchRule.Condition{field: :description, comparator: :contains, value: "NETFLIX"}],
        match_type: :all,
        account_name: ["Expenses", "Subscriptions"]
      }

      event = Reconciliation.execute(reconciliation, command)

      assert %MatchRuleSet{name: "Netflix", match_type: :all, account_name: ["Expenses", "Subscriptions"]} =
               event

      refute is_nil(event.id)

      reconciliation = Reconciliation.apply(reconciliation, event)
      assert [%{id: id, name: "Netflix"}] = reconciliation.match_rules
      assert id == event.id
    end

    test "update an existing rule preserves its position" do
      rule_a = %{id: Ecto.UUID.generate(), name: "A", conditions: [], match_type: :all, account_name: ["X"]}
      rule_b = %{id: Ecto.UUID.generate(), name: "B", conditions: [], match_type: :all, account_name: ["Y"]}
      reconciliation = %Reconciliation{match_rules: [rule_a, rule_b]}

      command = %SetMatchRule{
        id: rule_a.id,
        name: "A renamed",
        conditions: [%SetMatchRule.Condition{field: :description, comparator: :equals, value: "x"}],
        match_type: :all,
        account_name: ["X"]
      }

      event = Reconciliation.execute(reconciliation, command)
      reconciliation = Reconciliation.apply(reconciliation, event)

      assert [%{id: id_a, name: "A renamed"}, %{id: id_b, name: "B"}] = reconciliation.match_rules
      assert id_a == rule_a.id
      assert id_b == rule_b.id
    end

    test "remove a rule" do
      rule = %{id: Ecto.UUID.generate(), name: "A", conditions: [], match_type: :all, account_name: ["X"]}
      reconciliation = %Reconciliation{match_rules: [rule]}

      event = Reconciliation.execute(reconciliation, %RemoveMatchRule{id: rule.id})
      assert %MatchRuleRemoved{id: id} = event
      assert id == rule.id

      reconciliation = Reconciliation.apply(reconciliation, event)
      assert [] == reconciliation.match_rules
    end

    test "removing an unknown rule returns an error" do
      reconciliation = %Reconciliation{match_rules: []}

      assert {:error, %{id: ["not found"]}} =
               Reconciliation.execute(reconciliation, %RemoveMatchRule{id: Ecto.UUID.generate()})
    end

    test "reorder rules" do
      rule_a = %{id: Ecto.UUID.generate(), name: "A", conditions: [], match_type: :all, account_name: ["X"]}
      rule_b = %{id: Ecto.UUID.generate(), name: "B", conditions: [], match_type: :all, account_name: ["Y"]}
      reconciliation = %Reconciliation{match_rules: [rule_a, rule_b]}

      event = Reconciliation.execute(reconciliation, %ReorderMatchRules{ids: [rule_b.id, rule_a.id]})
      assert %MatchRulesReordered{ids: [id_b, id_a]} = event

      reconciliation = Reconciliation.apply(reconciliation, event)
      assert [%{id: ^id_b}, %{id: ^id_a}] = reconciliation.match_rules
    end

    test "reordering with a mismatched set of ids returns an error" do
      rule_a = %{id: Ecto.UUID.generate(), name: "A", conditions: [], match_type: :all, account_name: ["X"]}
      reconciliation = %Reconciliation{match_rules: [rule_a]}

      assert {:error, %{ids: ["must match existing rule ids"]}} =
               Reconciliation.execute(reconciliation, %ReorderMatchRules{ids: [Ecto.UUID.generate()]})
    end
  end
end
