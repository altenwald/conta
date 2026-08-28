defmodule Conta.Repo.Migrations.CreateBookInvoiceEmails do
  use Ecto.Migration

  def change do
    create table(:book_invoice_emails, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :invoice_id, references(:book_invoices, type: :binary_id, on_delete: :delete_all)
      add :to, :string
      add :subject, :string
      add :body, :text
      add :sent_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:book_invoice_emails, [:invoice_id, :sent_at])
  end
end
