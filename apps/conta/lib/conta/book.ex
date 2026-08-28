defmodule Conta.Book do
  import Conta.MoneyHelpers
  import Ecto.Query, only: [from: 2]

  alias Conta.Command.RemoveExpense
  alias Conta.Command.RemoveInvoice
  alias Conta.Command.SendInvoiceEmail
  alias Conta.Command.SetExpense
  alias Conta.Command.SetInvoice
  alias Conta.Projector.Book.Expense
  alias Conta.Projector.Book.Invoice
  alias Conta.Projector.Book.InvoiceEmail
  alias Conta.Projector.Book.PaymentMethod
  alias Conta.Projector.Book.Template
  alias Conta.Repo

  @due_in_days 30

  def get_invoice_date_range do
    from(i in Invoice, select: {max(i.invoice_date), min(i.invoice_date)})
    |> Repo.one()
  end

  def get_expense_date_range do
    from(e in Expense, select: {max(e.invoice_date), min(e.invoice_date)})
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

  defp by_client(query, nil), do: query
  defp by_client(query, ""), do: query

  defp by_client(query, client_id) when is_binary(client_id) do
    nif =
      case Ecto.UUID.cast(client_id) do
        {:ok, uuid} ->
          case Conta.Directory.get_contact(uuid) do
            %Conta.Projector.Directory.Contact{nif: nif} when is_binary(nif) and nif != "" -> nif
            _ -> client_id
          end

        :error ->
          client_id
      end

    from(i in query,
      where: fragment("?->>'nif' = ? OR ?->>'id' = ?", i.client, ^nif, i.client, ^client_id)
    )
  end

  def list_invoices_by_term_and_year(term, year, client \\ nil) do
    from(i in Invoice, order_by: [desc: :invoice_number])
    |> by_term(term)
    |> by_year(year)
    |> filter(client, &by_client/2)
    |> Repo.all()
  end

  def list_expenses_by_term_and_year(term, year) do
    from(e in Expense, order_by: [desc: :invoice_number])
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

  def list_invoices_filtered(filters, limit \\ :infinity) do
    from(i in Invoice, order_by: [desc: :invoice_number])
    |> filter(filters[:term], &by_term/2)
    |> filter(filters[:year], &by_year/2)
    |> filter(filters[:status], &by_status/2)
    |> filter(filters[:client] || filters[:client_id], &by_client/2)
    |> apply_limit(limit)
    |> Repo.all()
  end

  defp filter(query, nil, _f), do: query

  defp filter(query, value, f), do: f.(query, value)

  defp apply_limit(query, :infinity), do: query
  defp apply_limit(query, limit) when is_integer(limit), do: from(q in query, limit: ^limit)

  def list_simple_expenses_filtered(filters, limit \\ :infinity, offset \\ 0) do
    list_simple_expenses_query(limit, offset)
    |> filter(filters[:term], &by_term/2)
    |> filter(filters[:year], &by_year/2)
    |> Repo.all()
  end

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
        name: e.name,
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

  def list_invoices(limit \\ :infinity, offset \\ 0, client \\ nil) do
    list_invoices_query(limit, offset)
    |> filter(client, &by_client/2)
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

  def list_invoice_emails(invoice_id) do
    from(e in InvoiceEmail, where: e.invoice_id == ^invoice_id, order_by: [desc: e.sent_at])
    |> Repo.all()
  end

  def send_invoices_email(invoices, to_email, params, attachments \\ [])

  def send_invoices_email(%Invoice{} = invoice, to_email, params, attachments) do
    send_invoices_email([invoice], to_email, params, attachments)
  end

  def send_invoices_email([first_invoice | _] = invoices, to_email, params, attachments) do
    email = build_invoice_swoosh_email(first_invoice, to_email, params, attachments)

    with {:ok, _} <- Conta.Mailer.deliver(email) do
      dispatch_invoices_email_commands(invoices, to_email, params)
      {:ok, email}
    end
  end

  defp build_invoice_swoosh_email(invoice, to_email, params, attachments) do
    from_name = invoice.company.name || "Conta"
    default_from = Application.get_env(:conta, :mailer_from, "billing@altenwald.com")
    from_email = params[:from] || invoice.company.email || default_from

    Swoosh.Email.new()
    |> Swoosh.Email.to(to_email)
    |> Swoosh.Email.from({from_name, from_email})
    |> Swoosh.Email.subject(params[:subject] || "")
    |> Swoosh.Email.text_body(params[:body] || "")
    |> attach_files(attachments)
  end

  defp attach_files(email, attachments) do
    Enum.reduce(attachments, email, fn {filename, content_type, data}, acc ->
      attachment = Swoosh.Attachment.new({:data, data}, filename: filename, content_type: content_type)
      Swoosh.Email.attachment(acc, attachment)
    end)
  end

  defp dispatch_invoices_email_commands(invoices, to_email, params) do
    now = DateTime.utc_now()

    Enum.each(invoices, fn invoice ->
      command = %SendInvoiceEmail{
        id: Ecto.UUID.generate(),
        invoice_id: invoice.id,
        company_nif: invoice.company.nif,
        to: to_email,
        subject: params[:subject],
        body: params[:body],
        sent_at: now
      }

      Conta.Commanded.Application.dispatch(command)
    end)
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

  def get_template_by_name(nif \\ nil, name)

  def get_template_by_name(nil, name) do
    get_template_by_name(Application.get_env(:conta, :default_company_nif), name)
  end

  def get_template_by_name(nif, nil) do
    get_template_by_name(nif, Application.get_env(:conta, :default_template))
  end

  def get_template_by_name(nif, name) do
    Repo.get_by(Template, name: name, nif: nif)
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
    invoice_number =
      invoice.invoice_number
      |> String.split("-")
      |> List.last()
      |> String.to_integer()

    %RemoveInvoice{
      nif: invoice.company.nif,
      invoice_number: invoice_number,
      invoice_date: invoice.invoice_date
    }
  end

  def get_credit_note_by_origin_invoice_id(origin_id) do
    from(i in Invoice, where: i.origin_invoice_id == ^origin_id and i.is_credit_note == true, limit: 1)
    |> Repo.one()
  end

  def get_credit_note_by_origin_invoice_number(origin_number) do
    from(i in Invoice,
      where: i.origin_invoice_number == ^origin_number and i.is_credit_note == true,
      limit: 1
    )
    |> Repo.one()
  end

  def create_credit_note_from_invoice(invoice_or_id, overrides \\ %{})

  def create_credit_note_from_invoice(id, overrides) when is_binary(id) do
    invoice = get_invoice!(id)
    create_credit_note_from_invoice(invoice, overrides)
  end

  def create_credit_note_from_invoice(%Invoice{} = invoice, overrides) do
    details =
      for %Invoice.Detail{} = details <- invoice.details do
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

    today = Date.utc_today()

    command = %SetInvoice{
      action: :insert,
      nif: invoice.company.nif,
      name: invoice.name,
      client_nif: if(invoice.client, do: invoice.client.nif),
      destination_country: invoice.destination_country,
      template: invoice.template,
      invoice_date: Map.get(overrides, :invoice_date, today),
      due_date: Map.get(overrides, :due_date, Date.add(today, @due_in_days)),
      type: invoice.type,
      subtotal_price: to_money(invoice.subtotal_price) |> Money.to_decimal(),
      tax_price: to_money(invoice.tax_price) |> Money.to_decimal(),
      total_price: to_money(invoice.total_price) |> Money.to_decimal(),
      currency: to_string(invoice.currency),
      comments: Map.get(overrides, :comments, invoice.comments),
      payment_method: if(invoice.payment_method, do: invoice.payment_method.slug),
      is_credit_note: true,
      origin_invoice_number: invoice.invoice_number,
      origin_invoice_date: invoice.invoice_date,
      origin_invoice_id: invoice.id,
      details: details
    }

    case Conta.Commanded.Application.dispatch(command) do
      :ok ->
        {:ok, command}

      {:error, _reason} = error ->
        error
    end
  end

  def get_duplicate_expense(id) when is_binary(id),
    do: get_duplicate_expense(get_expense!(id))

  def get_duplicate_expense(%Expense{} = expense) do
    %SetExpense{
      action: :insert,
      name: expense.name,
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
      name: invoice.name,
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
      payment_method: if(invoice.payment_method, do: invoice.payment_method.slug),
      details:
        for %Invoice.Detail{} = details <- invoice.details do
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
      name: expense.name,
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
      attachments:
        for %Expense.Attachment{} = attachment <- expense.attachments do
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
    invoice_number =
      invoice.invoice_number
      |> String.split("-")
      |> List.last()
      |> String.to_integer()

    %SetInvoice{
      action: :update,
      name: invoice.name,
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
      payment_method: if(invoice.payment_method, do: invoice.payment_method.slug),
      is_credit_note: invoice.is_credit_note,
      origin_invoice_number: invoice.origin_invoice_number,
      origin_invoice_date: invoice.origin_invoice_date,
      origin_invoice_id: invoice.origin_invoice_id,
      details:
        for %Invoice.Detail{} = details <- invoice.details do
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
    get_last_invoice_number(Date.utc_today().year)
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
