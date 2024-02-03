defmodule Conta.Repo.Migrations.CreateBookTemplates do
  use Ecto.Migration

  def change do
    create table(:book_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :nif, :string
      add :name, :string
      add :css, :text
      add :logo, :binary
      add :logo_mime_type, :string

      timestamps()
    end

    create unique_index(:book_templates, [:name])
  end
end
