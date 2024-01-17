defmodule Conta.Repo.Migrations.CreateStatsIncome do
  use Ecto.Migration

  def change do
    create table(:stats_income, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_name, {:array, :string}
      add :year, :integer
      add :month, :integer
      add :currency, :string
      add :balance, :integer

      timestamps()
    end

    create unique_index(:stats_income, [:account_name, :year, :month, :currency])
  end
end
