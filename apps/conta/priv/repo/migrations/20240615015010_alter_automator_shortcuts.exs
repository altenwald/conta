defmodule Conta.Repo.Migrations.AlterAutomatorShortcuts do
  use Ecto.Migration

  def change do
    drop unique_index(:ledger_shortcuts, [:name, :ledger])

    rename table(:ledger_shortcuts), to: table("automator_shortcuts")
    rename table(:automator_shortcuts), :ledger, to: :automator

    create unique_index(:automator_shortcuts, [:name, :automator])
  end
end
