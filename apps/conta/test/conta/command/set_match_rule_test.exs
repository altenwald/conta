defmodule Conta.Command.SetMatchRuleTest do
  use ExUnit.Case

  alias Conta.Command.SetMatchRule

  describe "changeset/2" do
    test "valid with one condition" do
      params = %{
        "name" => "Netflix",
        "conditions" => [%{"field" => "description", "comparator" => "contains", "value" => "NETFLIX"}],
        "match_type" => "all",
        "account_name" => ["Expenses", "Subscriptions"]
      }

      changeset = SetMatchRule.changeset(params)
      assert changeset.valid?
    end

    test "invalid without conditions" do
      params = %{
        "name" => "Netflix",
        "conditions" => [],
        "match_type" => "all",
        "account_name" => ["Expenses"]
      }

      changeset = SetMatchRule.changeset(params)
      refute changeset.valid?
      assert %{conditions: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid comparator for amount field" do
      params = %{
        "name" => "x",
        "conditions" => [%{"field" => "amount", "comparator" => "contains", "value" => "10"}],
        "match_type" => "all",
        "account_name" => ["Expenses"]
      }

      changeset = SetMatchRule.changeset(params)
      refute changeset.valid?
    end

    test "casts id and reconciliation through to_command/1" do
      params = %{
        "id" => "abc-123",
        "reconciliation" => "recon-1",
        "name" => "Netflix",
        "conditions" => [%{"field" => "description", "comparator" => "contains", "value" => "NETFLIX"}],
        "match_type" => "all",
        "account_name" => ["Expenses", "Subscriptions"]
      }

      command =
        params
        |> SetMatchRule.changeset()
        |> SetMatchRule.to_command()

      assert command.id == "abc-123"
      assert command.reconciliation == "recon-1"
    end

    test "invalid between comparator without value_to" do
      params = %{
        "name" => "x",
        "conditions" => [%{"field" => "on_date", "comparator" => "between", "value" => "2024-01-01"}],
        "match_type" => "all",
        "account_name" => ["Expenses"]
      }

      changeset = SetMatchRule.changeset(params)
      refute changeset.valid?
    end

    test "valid between comparator with value_to" do
      params = %{
        "name" => "x",
        "conditions" => [
          %{
            "field" => "on_date",
            "comparator" => "between",
            "value" => "2024-01-01",
            "value_to" => "2024-01-31"
          }
        ],
        "match_type" => "all",
        "account_name" => ["Expenses"]
      }

      changeset = SetMatchRule.changeset(params)
      assert changeset.valid?
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
