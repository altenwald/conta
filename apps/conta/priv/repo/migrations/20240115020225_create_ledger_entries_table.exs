defmodule Conta.Repo.Migrations.CreateEntriesTable do
  use Ecto.Migration

  def change do
    create table(:ledger_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :on_date, :date
      add :description, :string
      add :credit, :integer
      add :debit, :integer
      add :balance, :integer
      add :transaction_id, :binary_id
      add :account_name, {:array, :string}
      add :breakdown, :boolean
      add :related_account_name, {:array, :string}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:ledger_entries, [:transaction_id])
    create index(:ledger_entries, [:account_name])
  end
end
