defmodule Conta.Repo.Migrations.CreateBookExpenses do
  use Ecto.Migration

  def change do
    create table(:book_expenses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :invoice_number, :string
      add :invoice_date, :date
      add :due_date, :date
      add :category, :string
      add :subtotal_price, :integer
      add :tax_price, :integer
      add :total_price, :integer
      add :comments, :string
      add :currency, :string

      add :provider, :jsonb
      add :company, :jsonb
      add :payment_method, :jsonb

      add :attachments, {:array, :jsonb}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:book_expenses, [:invoice_number])
  end
end
