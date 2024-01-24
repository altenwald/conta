defmodule Conta.Repo.Migrations.CreateAccountsTable do
  use Ecto.Migration

  def change do
    create table(:ledger_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string
      add :name, {:array, :string}
      add :ledger, :string
      add :currency, :string
      add :notes, :string
      add :parent_id, references(:ledger_accounts, on_delete: :nothing, type: :binary_id)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:ledger_accounts, [:name, :ledger])
  end
end
