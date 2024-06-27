defmodule Conta.Repo.Migrations.CreateAutomatorFilters do
  use Ecto.Migration

  def change do
    create table(:automator_filters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :automator, :string
      add :output, :string
      add :description, :string
      add :params, :jsonb
      add :code, :text
      add :language, :string
    end

    create unique_index(:automator_filters, [:name, :automator])
  end
end
