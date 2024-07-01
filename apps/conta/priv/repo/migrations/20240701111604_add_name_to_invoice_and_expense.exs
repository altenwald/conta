defmodule Conta.Repo.Migrations.AddNameToInvoiceAndExpense do
  use Ecto.Migration

  def change do
    alter table(:book_invoices) do
      add :name, :string
    end

    alter table(:book_expenses) do
      add :name, :string
    end
  end
end
