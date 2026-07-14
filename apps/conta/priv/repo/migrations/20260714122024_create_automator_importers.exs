defmodule Conta.Repo.Migrations.CreateAutomatorImporters do
  use Ecto.Migration

  def change do
    create table(:automator_importers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :automator, :string
      add :description, :string
      add :code, :text
      add :language, :string
    end

    create unique_index(:automator_importers, [:name, :automator])
  end
end
