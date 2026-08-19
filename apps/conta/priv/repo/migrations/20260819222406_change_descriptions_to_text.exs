defmodule Conta.Repo.Migrations.ChangeDescriptionsToText do
  use Ecto.Migration

  def change do
    alter table(:reconciliation_movements) do
      modify :description, :text, from: :string
    end

    alter table(:reconciliation_match_rules) do
      modify :concept, :text, from: :string
    end

    alter table(:ledger_entries) do
      modify :description, :text, from: :string
    end
  end
end
