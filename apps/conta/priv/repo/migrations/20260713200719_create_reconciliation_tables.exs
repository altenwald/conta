defmodule Conta.Repo.Migrations.CreateReconciliationTables do
  use Ecto.Migration

  def change do
    create table(:reconciliation_match_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :conditions, :jsonb
      add :match_type, :string
      add :account_name, {:array, :string}
      add :position, :integer
    end

    create index(:reconciliation_match_rules, [:position])

    create table(:reconciliation_movements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :on_date, :date
      add :description, :string
      add :amount, :integer
      add :currency, :string
      add :asset_account_name, {:array, :string}
      add :account_name, {:array, :string}
      add :source, :string
      add :transacted, :boolean, default: false
    end

    create index(:reconciliation_movements, [:asset_account_name])
  end
end
