defmodule Conta.Book do
  import Conta.MoneyHelpers
  import Ecto.Query, only: [from: 2]

  alias Conta.Command.RemoveExpense
  alias Conta.Command.RemoveInvoice
  alias Conta.Command.SetExpense
  alias Conta.Command.SetInvoice
  alias Conta.Projector.Book.Expense
  alias Conta.Projector.Book.Invoice
  alias Conta.Projector.Book.PaymentMethod
  alias Conta.Projector.Book.Template
  alias Conta.Repo

  @due_in_days 30

  def get_date_range do
    from(i in Invoice, select: {max(i.invoice_date), min(i.invoice_date)})
    |> Repo.one()
  end

  defp by_term(query, nil), do: query
  defp by_term(query, "Q1"), do: by_term(query, [1, 2, 3])
  defp by_term(query, "Q2"), do: by_term(query, [4, 5, 6])
  defp by_term(query, "Q3"), do: by_term(query, [7, 8, 9])
  defp by_term(query, "Q4"), do: by_term(query, [10, 11, 12])

  defp by_term(query, list) when is_list(list) do
    from(i in query, where: fragment("EXTRACT(MONTH FROM ?)", i.invoice_date) in ^list)
  end

  defp by_year(query, nil), do: query

  defp by_year(query, year) when is_binary(year) do
    by_year(query, String.to_integer(year))
  end

  defp by_year(query, year) when is_integer(year) do
    from(i in query, where: fragment("EXTRACT(YEAR FROM ?)", i.invoice_date) == ^year)
  end

  def list_invoices_by_term_and_year(term, year) do
    from(i in Invoice, order_by: [desc: :invoice_number])
    |> by_term(term)
    |> by_year(year)
    |> Repo.all()
  end

  defp by_status(query, "paid") do
    from(i in query, where: not is_nil(i.paid_date))
  end

  defp by_status(query, "unpaid") do
    from(i in query, where: is_nil(i.paid_date))
  end

  defp by_status(query, ""), do: query

  def list_invoices_filtered(filters) do
    from(i in Invoice, order_by: [desc: :invoice_number])
    |> filter(filters[:term], &by_term/2)
    |> filter(filters[:year], &by_year/2)
    |> filter(filters[:status], &by_status/2)
    |> Repo.all()
  end

  defp filter(query, nil, _f), do: query

  defp filter(query, value, f), do: f.(query, value)

  def list_simple_expenses(limit \\ :infinity, offset \\ 0) do
    list_simple_expenses_query(limit, offset)
    |> Repo.all()
  end

  defp list_simple_expenses_query(:infinity, _offset) do
    from(
      e in Expense,
      order_by: [
        desc: e.invoice_date,
        asc: e.invoice_number
      ],
      select: %Expense{
        id: e.id,
        invoice_number: e.invoice_number,
        invoice_date: e.invoice_date,
        due_date: e.due_date,
        category: e.category,
        subtotal_price: e.subtotal_price,
        tax_price: e.tax_price,
        total_price: e.total_price,
        comments: e.comments,
        currency: e.currency,
        provider: e.provider,
        company: e.company,
        payment_method: e.payment_method,
        inserted_at: e.inserted_at,
        updated_at: e.updated_at,
        num_attachments: fragment("coalesce(array_length(?, 1), 0)", e.attachments)
      }
    )
  end

  defp list_simple_expenses_query(limit, offset) when is_integer(limit) and is_integer(offset) do
    query = list_simple_expenses_query(:infinity, 0)
    from(e in query, limit: ^limit, offset: ^offset)
  end

  def list_invoices(limit \\ :infinity, offset \\ 0) do
    list_invoices_query(limit, offset)
    |> Repo.all()
  end

  defp list_invoices_query(:infinity, _offset) do
    from(i in Invoice, order_by: [desc: i.invoice_number])
  end

  defp list_invoices_query(limit, offset) when is_integer(limit) and is_integer(offset) do
    query = list_invoices_query(:infinity, 0)
    from(i in query, limit: ^limit, offset: ^offset)
  end

  def get_expense!(id), do: Repo.get!(Expense, id)

  def get_expense(id), do: Repo.get(Expense, id)

  def get_invoice!(id), do: Repo.get!(Invoice, id)

  def get_invoice(id), do: Repo.get(Invoice, id)

  def get_invoice!(year, number) when is_integer(year) and is_integer(number) do
    invoice_number = "#{year}-#{String.pad_leading(to_string(number), 5, "0")}"
    Repo.get_by!(Invoice, invoice_number: invoice_number)
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

  def get_remove_expense(id) when is_binary(id),
    do: get_remove_expense(get_expense!(id))

  def get_remove_expense(%Expense{} = expense) do
    %RemoveExpense{
      nif: expense.company.nif,
      invoice_number: expense.invoice_number,
      invoice_date: expense.invoice_date
    }
  end

  def get_remove_invoice(id) when is_binary(id),
    do: get_remove_invoice(get_invoice!(id))

  def get_remove_invoice(%Invoice{} = invoice) do
    [_year, invoice_number] = String.split(invoice.invoice_number, "-", parts: 2)
    invoice_number = String.to_integer(invoice_number)

    %RemoveInvoice{
      nif: invoice.company.nif,
      invoice_number: invoice_number,
      invoice_date: invoice.invoice_date
    }
  end

  def get_duplicate_expense(id) when is_binary(id),
    do: get_duplicate_expense(get_expense!(id))

  def get_duplicate_expense(%Expense{} = expense) do
    %SetExpense{
      action: :insert,
      nif: expense.company.nif,
      provider_nif: expense.provider.nif,
      invoice_number: expense.invoice_number,
      invoice_date: Date.utc_today(),
      due_date: Date.add(Date.utc_today(), @due_in_days),
      category: expense.category,
      subtotal_price: to_money(expense.subtotal_price) |> Money.to_decimal(),
      tax_price: to_money(expense.tax_price) |> Money.to_decimal(),
      total_price: to_money(expense.total_price) |> Money.to_decimal(),
      currency: expense.currency,
      comments: expense.comments,
      payment_method: expense.payment_method.slug
    }
  end

  def get_duplicate_invoice(id) when is_binary(id),
    do: get_duplicate_invoice(get_invoice!(id))

  def get_duplicate_invoice(%Invoice{} = invoice) do
    invoice_number = get_last_invoice_number() + 1

    %SetInvoice{
      action: :insert,
      nif: invoice.company.nif,
      client_nif: invoice.client && invoice.client.nif,
      template: invoice.template,
      invoice_number: invoice_number,
      invoice_date: Date.utc_today(),
      due_date: Date.add(Date.utc_today(), @due_in_days),
      type: invoice.type,
      subtotal_price: to_money(invoice.subtotal_price) |> Money.to_decimal(),
      tax_price: to_money(invoice.tax_price) |> Money.to_decimal(),
      total_price: to_money(invoice.total_price) |> Money.to_decimal(),
      currency: invoice.currency,
      comments: invoice.comments,
      destination_country: invoice.destination_country,
      payment_method: invoice.payment_method.slug,
      details: for %Invoice.Detail{} = details <- invoice.details do
        %SetInvoice.Detail{
          sku: details.sku,
          description: details.description,
          tax: details.tax,
          base_price: to_money(details.base_price) |> Money.to_decimal(),
          units: details.units,
          tax_price: to_money(details.tax_price) |> Money.to_decimal(),
          total_price: to_money(details.total_price) |> Money.to_decimal()
        }
      end
    }
  end

  def get_set_expense(id) when is_binary(id),
    do: get_set_expense(get_expense!(id))

  def get_set_expense(%Expense{} = expense) do
    %SetExpense{
      action: :update,
      nif: expense.company.nif,
      provider_nif: expense.provider.nif,
      invoice_number: expense.invoice_number,
      invoice_date: expense.invoice_date,
      due_date: expense.due_date,
      category: expense.category,
      subtotal_price: to_money(expense.subtotal_price) |> Money.to_decimal(),
      tax_price: to_money(expense.tax_price) |> Money.to_decimal(),
      total_price: to_money(expense.total_price) |> Money.to_decimal(),
      currency: expense.currency,
      comments: expense.comments,
      payment_method: expense.payment_method.slug,
      attachments: for %Expense.Attachment{} = attachment <- expense.attachments do
        %SetExpense.Attachment{
          id: attachment.id,
          name: attachment.name,
          file: attachment.file,
          mimetype: attachment.mimetype,
          size: attachment.size,
          inserted_at: attachment.inserted_at,
          updated_at: attachment.updated_at
        }
      end
    }
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
      subtotal_price: to_money(invoice.subtotal_price) |> Money.to_decimal(),
      tax_price: to_money(invoice.tax_price) |> Money.to_decimal(),
      total_price: to_money(invoice.total_price) |> Money.to_decimal(),
      currency: invoice.currency,
      comments: invoice.comments,
      destination_country: invoice.destination_country,
      payment_method: invoice.payment_method.slug,
      details: for %Invoice.Detail{} = details <- invoice.details do
        %SetInvoice.Detail{
          id: details.id,
          sku: details.sku,
          description: details.description,
          tax: details.tax,
          base_price: to_money(details.base_price) |> Money.to_decimal(),
          units: details.units,
          tax_price: to_money(details.tax_price) |> Money.to_decimal(),
          total_price: to_money(details.total_price) |> Money.to_decimal()
        }
      end
    }
  end

  def new_set_expense do
    %SetExpense{
      action: :insert,
      nif: Application.get_env(:conta, :default_company_nif),
      invoice_date: Date.utc_today(),
      currency: Application.get_env(:conta, :frequent_currencies, [nil]) |> hd()
    }
  end

  def new_set_invoice do
    invoice_number = get_last_invoice_number() + 1

    %SetInvoice{
      action: :insert,
      nif: Application.get_env(:conta, :default_company_nif),
      invoice_number: invoice_number,
      invoice_date: Date.utc_today(),
      currency: Application.get_env(:conta, :frequent_currencies, [nil]) |> hd()
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
