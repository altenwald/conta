defmodule Conta.Book do
  import Ecto.Query, only: [from: 2]
  alias Conta.Command.SetInvoice
  alias Conta.Projector.Book.Invoice
  alias Conta.Projector.Book.PaymentMethod
  alias Conta.Projector.Book.Template
  alias Conta.Repo

  def list_invoices(limit \\ :infinity)

  def list_invoices(:infinity) do
    from(
      i in Invoice,
      order_by: [desc: fragment("extract(year from ?)", i.invoice_date), desc: i.invoice_number]
    )
    |> Repo.all()
  end

  def list_invoices(limit) when is_integer(limit) do
    from(
      i in Invoice,
      order_by: [desc: fragment("extract(year from ?)", i.invoice_date), desc: i.invoice_number],
      limit: ^limit
    )
    |> Repo.all()
  end

  def get_invoice!(id) do
    Repo.get!(Invoice, id)
  end

  def list_payment_methods(nif \\ nil)

  def list_payment_methods(nil) do
    list_payment_methods(Application.get_env(:conta, :default_company_nif))
  end

  def list_payment_methods(nif) do
    from(p in PaymentMethod, where: p.nif == ^nif, order_by: p.name)
    |> Repo.all()
  end

  def list_templates(nif \\ nil)

  def list_templates(nil) do
    list_templates(Application.get_env(:conta, :default_company_nif))
  end

  def list_templates(nif) do
    from(t in Template, where: t.nif == ^nif, order_by: t.name)
    |> Repo.all()
  end

  def get_template_by_name!(nif \\ nil, name)

  def get_template_by_name!(nil, name) do
    get_template_by_name!(Application.fetch_env!(:conta, :default_company_nif), name)
  end

  def get_template_by_name!(nif, nil) do
    get_template_by_name!(nif, Application.fetch_env!(:conta, :default_template))
  end

  def get_template_by_name!(nif, name) do
    Repo.get_by!(Template, name: name, nif: nif)
  end

  def get_set_invoice(id) when is_binary(id),
    do: get_set_invoice(get_invoice!(id))

  def get_set_invoice(%Invoice{} = invoice) do
    [_year, invoice_number] = String.split(invoice.invoice_number, "-", parts: 2)
    invoice_number = String.to_integer(invoice_number)

    %SetInvoice{
      action: :update,
      nif: invoice.company.nif,
      client_nif: invoice.client && invoice.client.nif,
      template: invoice.template,
      invoice_number: invoice_number,
      invoice_date: invoice.invoice_date,
      paid_date: invoice.paid_date,
      due_date: invoice.due_date,
      type: invoice.type,
      subtotal_price: invoice.subtotal_price,
      tax_price: invoice.tax_price,
      total_price: invoice.total_price,
      currency: invoice.currency,
      comments: invoice.comments,
      destination_country: invoice.destination_country,
      payment_method: invoice.payment_method,
      details: for %Invoice.Detail{} = details <- invoice.details do
        %SetInvoice.Detail{
          sku: details.sku,
          description: details.description,
          tax: details.tax,
          base_price: details.base_price,
          units: details.units,
          tax_price: details.tax_price,
          total_price: details.total_price
        }
      end
    }
  end

  def new_set_invoice do
    invoice_number = get_last_invoice_number() + 1

    %SetInvoice{
      action: :insert,
      nif: Application.get_env(:conta, :default_company_nif),
      invoice_number: invoice_number,
      invoice_date: Date.utc_today(),
    }
  end

  def get_last_invoice_number(year \\ nil)

  def get_last_invoice_number(nil) do
    get_last_invoice_number(Date.utc_today.year)
  end

  def get_last_invoice_number(year) when is_integer(year) do
    year_str = to_string(year)
    from(
      i in Invoice,
      where: fragment("extract(year from ?) = ?", i.invoice_date, ^year),
      order_by: [desc: i.invoice_number],
      limit: 1,
      select: i.invoice_number
    )
    |> Repo.one()
    |> case do
      nil -> 0
      <<^year_str::binary-size(4), "-", value::binary>> -> String.to_integer(value)
    end
  end
end
