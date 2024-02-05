defmodule Conta.Repo.Migrations.CreateLedgerShortcuts do
  use Ecto.Migration

  def change do
    create table(:ledger_shortcuts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :ledger, :string
      add :description, :string
      add :params, :jsonb
      add :code, :text
      add :language, :string
    end

    create unique_index(:ledger_shortcuts, [:name, :ledger])
  end
end
