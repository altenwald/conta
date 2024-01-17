defmodule Conta.Repo.Migrations.CreateStatsPatrimony do
  use Ecto.Migration

  def change do
    create table(:stats_patrimony, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :year, :integer
      add :month, :integer
      add :currency, :string
      add :amount, :integer
      add :balance, :integer

      timestamps()
    end

    create unique_index(:stats_patrimony, [:year, :month, :currency])
  end
end
