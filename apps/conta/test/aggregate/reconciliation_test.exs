defmodule Conta.Aggregate.ReconciliationTest do
  use ExUnit.Case

  alias Conta.Aggregate.Reconciliation

  alias Conta.Command.RemoveMatchRule
  alias Conta.Command.ReorderMatchRules
  alias Conta.Command.SetMatchRule

  alias Conta.Event.MatchRuleRemoved
  alias Conta.Event.MatchRuleSet
  alias Conta.Event.MatchRulesReordered

  alias Conta.Command.ImportMovements
  alias Conta.Event.MovementsImported

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

    test "updating with an unknown id returns an error instead of creating a new rule" do
      reconciliation = %Reconciliation{match_rules: []}

      command = %SetMatchRule{
        id: Ecto.UUID.generate(),
        name: "Ghost",
        conditions: [%SetMatchRule.Condition{field: :description, comparator: :equals, value: "x"}],
        match_type: :all,
        account_name: ["X"]
      }

      assert {:error, %{id: ["not found"]}} = Reconciliation.execute(reconciliation, command)
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

  describe "import movements" do
    setup do
      netflix_rule = %{
        id: Ecto.UUID.generate(),
        name: "Netflix",
        conditions: [%{field: :description, comparator: :contains, value: "NETFLIX", value_to: nil}],
        match_type: :all,
        account_name: ["Expenses", "Subscriptions"]
      }

      %{reconciliation: %Reconciliation{match_rules: [netflix_rule]}, netflix_rule: netflix_rule}
    end

    test "a movement matching a rule gets account_name proposed", %{reconciliation: reconciliation} do
      command = %ImportMovements{
        movements: [
          %ImportMovements.Movement{
            on_date: ~D[2026-07-01],
            description: "NETFLIX.COM SUBSCRIPTION",
            amount: -1399,
            currency: :EUR,
            asset_account_name: ["Assets", "Bank"]
          }
        ]
      }

      event = Reconciliation.execute(reconciliation, command)

      assert %MovementsImported{movements: [movement]} = event
      assert movement.account_name == ["Expenses", "Subscriptions"]
      assert movement.description == "NETFLIX.COM SUBSCRIPTION"
      refute is_nil(movement.id)
      refute movement.transacted

      reconciliation = Reconciliation.apply(reconciliation, event)
      assert map_size(reconciliation.movements) == 1
      assert [{_id, %{account_name: ["Expenses", "Subscriptions"]}}] = Map.to_list(reconciliation.movements)
    end

    test "a movement matching no rule gets account_name nil", %{reconciliation: reconciliation} do
      command = %ImportMovements{
        movements: [
          %ImportMovements.Movement{
            on_date: ~D[2026-07-01],
            description: "UNKNOWN TRANSFER",
            amount: -4530,
            currency: :EUR,
            asset_account_name: ["Assets", "Bank"]
          }
        ]
      }

      assert %MovementsImported{movements: [%{account_name: nil}]} =
               Reconciliation.execute(reconciliation, command)
    end

    test "first matching rule wins when several would match", %{netflix_rule: netflix_rule} do
      second_rule = %{
        id: Ecto.UUID.generate(),
        name: "Also contains NETFLIX",
        conditions: [%{field: :description, comparator: :contains, value: "NETFLIX", value_to: nil}],
        match_type: :all,
        account_name: ["Expenses", "Other"]
      }

      reconciliation = %Reconciliation{match_rules: [netflix_rule, second_rule]}

      command = %ImportMovements{
        movements: [
          %ImportMovements.Movement{
            on_date: ~D[2026-07-01],
            description: "NETFLIX.COM",
            amount: -1399,
            currency: :EUR,
            asset_account_name: ["Assets", "Bank"]
          }
        ]
      }

      assert %MovementsImported{movements: [%{account_name: ["Expenses", "Subscriptions"]}]} =
               Reconciliation.execute(reconciliation, command)
    end

    test "match_type any requires only one condition to hold" do
      rule = %{
        id: Ecto.UUID.generate(),
        name: "big or Netflix",
        conditions: [
          %{field: :description, comparator: :contains, value: "NETFLIX", value_to: nil},
          %{field: :amount, comparator: :greater_than, value: "100000", value_to: nil}
        ],
        match_type: :any,
        account_name: ["Expenses", "Subscriptions"]
      }

      reconciliation = %Reconciliation{match_rules: [rule]}

      command = %ImportMovements{
        movements: [
          %ImportMovements.Movement{
            on_date: ~D[2026-07-01],
            description: "totally unrelated",
            amount: 200_000,
            currency: :EUR,
            asset_account_name: ["Assets", "Bank"]
          }
        ]
      }

      assert %MovementsImported{movements: [%{account_name: ["Expenses", "Subscriptions"]}]} =
               Reconciliation.execute(reconciliation, command)
    end

    test "on_date between condition" do
      rule = %{
        id: Ecto.UUID.generate(),
        name: "July",
        conditions: [%{field: :on_date, comparator: :between, value: "2026-07-01", value_to: "2026-07-31"}],
        match_type: :all,
        account_name: ["Expenses", "Misc"]
      }

      reconciliation = %Reconciliation{match_rules: [rule]}

      in_range = %ImportMovements.Movement{
        on_date: ~D[2026-07-15],
        description: "x",
        amount: -100,
        currency: :EUR,
        asset_account_name: ["Assets", "Bank"]
      }

      out_of_range = %ImportMovements.Movement{
        on_date: ~D[2026-08-01],
        description: "x",
        amount: -100,
        currency: :EUR,
        asset_account_name: ["Assets", "Bank"]
      }

      command = %ImportMovements{movements: [in_range, out_of_range]}

      assert %MovementsImported{movements: [matched, unmatched]} =
               Reconciliation.execute(reconciliation, command)

      assert matched.account_name == ["Expenses", "Misc"]
      assert is_nil(unmatched.account_name)
    end
  end
end
