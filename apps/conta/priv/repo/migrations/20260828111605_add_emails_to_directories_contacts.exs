defmodule Conta.Repo.Migrations.AddEmailsToDirectoriesContacts do
  use Ecto.Migration

  def change do
    alter table(:directories_contacts) do
      add :emails, {:array, :string}, default: []
    end
  end
end
