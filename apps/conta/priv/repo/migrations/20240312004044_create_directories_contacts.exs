defmodule Conta.Repo.Migrations.CreateDirectoriesContacts do
  use Ecto.Migration

  def change do
    create table(:directories_contacts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :company_nif, :string
      add :name, :string
      add :nif, :string
      add :intracommunity, :boolean
      add :address, :string
      add :postcode, :string
      add :city, :string
      add :state, :string
      add :country, :string
    end

    create unique_index(:directories_contacts, [:company_nif, :nif])
  end
end
