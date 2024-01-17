defmodule Conta.Repo.Migrations.CreateStatsProfitsLoses do
  use Ecto.Migration

  def change do
    create table(:stats_profits_loses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :year, :integer
      add :month, :integer
      add :currency, :string
      add :profits, :integer
      add :loses, :integer
      add :balance, :integer

      timestamps()
    end

    create unique_index(:stats_profits_loses, [:year, :month, :currency])
  end
end
