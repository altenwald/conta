defmodule Conta.Repo.Migrations.AddChangeValuesToLedgerEntries do
  use Ecto.Migration

  def change do
    alter table(:ledger_entries) do
      add :change_currency, :string
      add :change_credit, :integer
      add :change_debit, :integer
    end
  end
end
