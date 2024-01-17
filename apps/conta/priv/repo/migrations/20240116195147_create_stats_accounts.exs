defmodule Conta.Repo.Migrations.CreateStatsAccounts do
  use Ecto.Migration

  def change do
    create table(:stats_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string
      add :name, {:array, :string}
      add :ledger, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:stats_accounts, [:name, :ledger])
  end
end
