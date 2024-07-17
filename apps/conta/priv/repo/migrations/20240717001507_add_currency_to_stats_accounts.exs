defmodule Conta.Repo.Migrations.AddCurrencyToStatsAccounts do
  use Ecto.Migration

  def change do
    alter table(:stats_accounts) do
      add(:currency, :string)
    end
  end
end
