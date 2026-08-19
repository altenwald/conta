defmodule Conta.Repo.Migrations.AddConceptToReconciliationMatchRules do
  use Ecto.Migration

  def change do
    alter table(:reconciliation_match_rules) do
      add :concept, :string
    end
  end
end
