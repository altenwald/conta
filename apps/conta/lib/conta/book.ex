defmodule Conta.Book do
  import Ecto.Query, only: [from: 2]
  alias Conta.Projector.Book.Invoice
  alias Conta.Command.CreateInvoice
  alias Conta.Repo

  def list_invoices do
    from(i in Invoice, order_by: i.invoice_date)
    |> Repo.all()
  end

  def new_create_invoice do
    invoice_number = get_last_invoice_number()

    %CreateInvoice{
      invoice_number: invoice_number,
      invoice_date: Date.utc_today()
    }
  end

  def get_last_invoice_number(year \\ nil)

  def get_last_invoice_number(nil) do
    get_last_invoice_number(Date.utc_today.year)
  end

  def get_last_invoice_number(year) do
    from(
      i in Invoice,
      where: fragment("extract(year from ?) = ?", i.invoice_date, ^year),
      order_by: [desc: i.invoice_number],
      limit: 1,
      select: i.invoice_number
    )
    |> Repo.one()
    |> case do
      nil -> 1
      value -> value
    end
  end
end
