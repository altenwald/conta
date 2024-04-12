defmodule Conta.Book do
  import Ecto.Query, only: [from: 2]
  alias Conta.Command.CreateInvoice
  alias Conta.Projector.Book.Invoice
  alias Conta.Projector.Book.PaymentMethod
  alias Conta.Projector.Book.Template
  alias Conta.Repo

  def list_invoices do
    from(
      i in Invoice,
      order_by: [desc: fragment("extract(year from ?)", i.invoice_date), desc: i.invoice_number]
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

  def new_create_invoice do
    invoice_number = get_last_invoice_number() + 1

    %CreateInvoice{
      nif: Application.get_env(:conta, :default_company_nif),
      invoice_number: invoice_number,
      invoice_date: Date.utc_today(),
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
      nil -> 0
      <<year::binary-size(4), "-", value::binary>> -> String.to_integer(value)
    end
  end
end
