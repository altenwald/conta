defmodule Conta.Repo.Migrations.CreateInvoices do
  use Ecto.Migration

  def change do
    create table(:invoices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :template, :string
      add :invoice_number, :string
      add :invoice_date, :date
      add :due_date, :date
      add :type, :string
      add :subtotal_price, :integer
      add :tax_price, :integer
      add :total_price, :integer
      add :comments, :string
      add :destination_country, :string

      add :client, :jsonb
      add :company, :jsonb
      add :payment_method, :jsonb

      add :details, {:array, :jsonb}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:invoices, [:invoice_number])
  end
end
