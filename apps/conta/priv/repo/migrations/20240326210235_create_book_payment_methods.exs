defmodule Conta.Repo.Migrations.CreateBookPaymentMethods do
  use Ecto.Migration

  def change do
    create table(:book_payment_methods, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :nif, :string
      add :name, :string
      add :slug, :string
      add :method, :string
      add :details, :string
      add :holder, :string
    end

    create unique_index(:book_payment_methods, [:nif, :slug])
  end
end
