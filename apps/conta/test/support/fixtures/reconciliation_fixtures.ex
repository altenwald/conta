defmodule Conta.ReconciliationFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Conta.Reconciliation` context.
  """
  use ExMachina.Ecto, repo: Conta.Repo

  alias Conta.Projector.Reconciliation.MatchRule
  alias Conta.Projector.Reconciliation.Movement

  def match_rule_factory do
    %MatchRule{
      id: Ecto.UUID.generate(),
      name: sequence(:name, &"rule #{&1}"),
      conditions: [
        %MatchRule.Condition{field: :description, comparator: :contains, value: "X"}
      ],
      match_type: :all,
      account_name: ["Expenses", "Misc"],
      position: sequence(:position, & &1)
    }
  end

  def movement_factory do
    %Movement{
      id: Ecto.UUID.generate(),
      on_date: ~D[2026-07-01],
      description: sequence(:description, &"movement #{&1}"),
      amount: -1000,
      currency: :EUR,
      asset_account_name: ["Assets", "Bank"],
      account_name: nil,
      source: "test importer",
      transacted: false
    }
  end
end
