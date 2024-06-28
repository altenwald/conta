defmodule Conta.Repo.Migrations.AddTypeToAutomatorFilters do
  use Ecto.Migration

  def change do
    alter table(:automator_filters) do
      add :type, :string, default: "all"
    end
  end
end
