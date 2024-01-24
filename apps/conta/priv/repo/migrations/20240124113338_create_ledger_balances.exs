defmodule Conta.Repo.Migrations.CreateLedgerBalances do
  use Ecto.Migration

  def change do
    create table(:ledger_balances, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :currency, :string
      add :amount, :integer
      add :account_id, references(:ledger_accounts, on_delete: :nothing, type: :binary_id)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:ledger_balances, [:account_id, :currency])
    create index(:ledger_balances, [:account_id])
  end
end
