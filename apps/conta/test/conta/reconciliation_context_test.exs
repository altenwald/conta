defmodule Conta.ReconciliationContextTest do
  use Conta.DataCase

  import Conta.ReconciliationFixtures

  alias Conta.Projector.Reconciliation.MatchRule
  alias Conta.Projector.Reconciliation.Movement
  alias Conta.Reconciliation

  describe "match rules" do
    test "list_match_rules/0 returns rules ordered by position" do
      rule_b = insert(:match_rule, position: 1)
      rule_a = insert(:match_rule, position: 0)

      assert [%MatchRule{id: id_a}, %MatchRule{id: id_b}] = Reconciliation.list_match_rules()
      assert id_a == rule_a.id
      assert id_b == rule_b.id
    end

    test "get_match_rule!/1 returns the rule" do
      rule = insert(:match_rule)
      assert %MatchRule{id: id} = Reconciliation.get_match_rule!(rule.id)
      assert id == rule.id
    end
  end

  describe "movements" do
    test "list_movements/0 returns all pending movements" do
      movement = insert(:movement)
      result = Reconciliation.list_movements()
      assert Enum.any?(result, &(&1.id == movement.id))
    end

    test "list_movements/0 splits by whether account_name is present" do
      with_account = insert(:movement, account_name: ["Expenses", "Misc"])
      without_account = insert(:movement, account_name: nil)

      result = Reconciliation.list_movements()
      assert Enum.find(result, &(&1.id == with_account.id))
      assert Enum.find(result, &(&1.id == without_account.id))
    end

    test "get_movement!/1 returns the movement" do
      movement = insert(:movement)
      assert %Movement{id: id} = Reconciliation.get_movement!(movement.id)
      assert id == movement.id
    end
  end
end
