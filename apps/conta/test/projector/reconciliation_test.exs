defmodule Conta.Projector.ReconciliationTest do
  use Conta.DataCase
  alias Conta.Projector.Reconciliation

  setup do
    version =
      if pv = Repo.get(Reconciliation.ProjectionVersion, "Conta.Projector.Reconciliation") do
        pv.last_seen_version + 1
      else
        1
      end

    on_exit(fn ->
      Repo.delete_all(Reconciliation.MatchRule)
      Repo.delete_all(Reconciliation.Movement)
      Repo.delete_all(Reconciliation.ProjectionVersion)
    end)

    %{handler_name: "Conta.Projector.Reconciliation", event_number: version}
  end

  describe "match rules" do
    test "MatchRuleSet inserts a row at the next position", metadata do
      event = %Conta.Event.MatchRuleSet{
        id: Ecto.UUID.generate(),
        name: "Netflix",
        conditions: [
          %Conta.Event.MatchRuleSet.Condition{field: :description, comparator: :contains, value: "NETFLIX"}
        ],
        match_type: :all,
        account_name: ["Expenses", "Subscriptions"]
      }

      assert :ok = Reconciliation.handle(event, metadata)

      assert %Reconciliation.MatchRule{name: "Netflix", position: 0} =
               Repo.get_by!(Reconciliation.MatchRule, id: event.id)
    end

    test "MatchRuleRemoved deletes the row", metadata do
      rule = insert_match_rule(position: 0)

      event = %Conta.Event.MatchRuleRemoved{id: rule.id}
      assert :ok = Reconciliation.handle(event, metadata)

      refute Repo.get(Reconciliation.MatchRule, rule.id)
    end

    test "MatchRulesReordered updates positions", metadata do
      rule_a = insert_match_rule(position: 0)
      rule_b = insert_match_rule(position: 1)

      event = %Conta.Event.MatchRulesReordered{ids: [rule_b.id, rule_a.id]}
      assert :ok = Reconciliation.handle(event, metadata)

      assert Repo.get!(Reconciliation.MatchRule, rule_b.id).position == 0
      assert Repo.get!(Reconciliation.MatchRule, rule_a.id).position == 1
    end
  end

  describe "movements" do
    test "MovementsImported inserts one row per movement", metadata do
      event = %Conta.Event.MovementsImported{
        movements: [
          %Conta.Event.MovementsImported.Movement{
            id: Ecto.UUID.generate(),
            on_date: ~D[2026-07-01],
            description: "x",
            amount: -100,
            currency: :EUR,
            asset_account_name: ["Assets", "Bank"],
            account_name: nil,
            transacted: false
          }
        ]
      }

      assert :ok = Reconciliation.handle(event, metadata)
      assert [%Reconciliation.Movement{description: "x"}] = Repo.all(Reconciliation.Movement)
    end

    test "MovementUpdated updates the row", metadata do
      movement = insert_movement()

      event = %Conta.Event.MovementUpdated{
        id: movement.id,
        on_date: movement.on_date,
        description: "new description",
        amount: movement.amount,
        currency: movement.currency,
        account_name: ["Expenses", "Manual"]
      }

      assert :ok = Reconciliation.handle(event, metadata)

      updated = Repo.get!(Reconciliation.Movement, movement.id)
      assert updated.description == "new description"
      assert updated.account_name == ["Expenses", "Manual"]
    end

    test "MovementUpdated with account_name: nil preserves the existing account_name", metadata do
      movement = insert_movement(account_name: ["Expenses", "Groceries"])

      event = %Conta.Event.MovementUpdated{
        id: movement.id,
        on_date: movement.on_date,
        description: "new description",
        amount: movement.amount,
        currency: movement.currency,
        account_name: nil
      }

      assert :ok = Reconciliation.handle(event, metadata)

      updated = Repo.get!(Reconciliation.Movement, movement.id)
      assert updated.description == "new description"
      assert updated.account_name == ["Expenses", "Groceries"]
    end

    test "MovementRemoved deletes the row", metadata do
      movement = insert_movement()

      assert :ok = Reconciliation.handle(%Conta.Event.MovementRemoved{id: movement.id}, metadata)
      refute Repo.get(Reconciliation.Movement, movement.id)
    end

    test "MovementTransacted sets transacted to true", metadata do
      movement = insert_movement()

      assert :ok = Reconciliation.handle(%Conta.Event.MovementTransacted{id: movement.id}, metadata)
      assert Repo.get!(Reconciliation.Movement, movement.id).transacted
    end
  end

  defp insert_match_rule(attrs) do
    %Reconciliation.MatchRule{}
    |> Reconciliation.MatchRule.changeset(
      Map.merge(
        %{id: Ecto.UUID.generate(), name: "rule", conditions: [], match_type: :all, account_name: ["X"]},
        Map.new(attrs)
      )
    )
    |> Repo.insert!()
  end

  defp insert_movement(attrs \\ %{}) do
    %Reconciliation.Movement{}
    |> Reconciliation.Movement.changeset(
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          on_date: ~D[2026-07-01],
          description: "x",
          amount: -100,
          currency: "EUR",
          asset_account_name: ["Assets", "Bank"],
          transacted: false
        },
        Map.new(attrs)
      )
    )
    |> Repo.insert!()
  end
end
