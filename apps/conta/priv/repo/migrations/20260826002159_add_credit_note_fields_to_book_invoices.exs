defmodule Conta.Repo.Migrations.AddCreditNoteFieldsToBookInvoices do
  use Ecto.Migration

  def change do
    alter table(:book_invoices) do
      add :is_credit_note, :boolean, default: false, null: false
      add :origin_invoice_number, :string
      add :origin_invoice_date, :date
      add :origin_invoice_id, :binary_id
    end

    create index(:book_invoices, [:is_credit_note])
    create index(:book_invoices, [:origin_invoice_number])
    create index(:book_invoices, [:origin_invoice_id])
  end
end

