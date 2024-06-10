defmodule Conta.Projector.Book do
  use Commanded.Projections.Ecto,
    application: Conta.Commanded.Application,
    repo: Conta.Repo,
    name: __MODULE__

  require Logger

  alias Conta.Event.ExpenseRemoved
  alias Conta.Event.ExpenseSet
  alias Conta.Event.InvoiceRemoved
  alias Conta.Event.InvoiceSet
  alias Conta.Event.PaymentMethodSet
  alias Conta.Event.TemplateSet

  alias Conta.Projector.Book.Expense
  alias Conta.Projector.Book.Invoice
  alias Conta.Projector.Book.PaymentMethod
  alias Conta.Projector.Book.Template

  defp to_integer(i) when is_integer(i), do: i

  defp to_integer(f) when is_float(f), do: ceil(f * 100)

  defp to_integer(str) when is_binary(str) do
    str
    |> Decimal.parse()
    |> then(fn {decimal, ""} -> to_integer(decimal) end)
  end

  defp to_integer(decimal) when is_struct(decimal, Decimal) do
    decimal
    |> Decimal.mult(100)
    |> Decimal.round(0, :ceiling)
    |> Decimal.to_integer()
  end

  defp to_invoice_number(date, number) when is_binary(date),
    do: to_invoice_number(Date.from_iso8601!(date), number)

  defp to_invoice_number(date, number) when is_struct(date, Date),
    do: to_invoice_number(date.year, number)

  defp to_invoice_number(year, number) when is_integer(number),
    do: to_invoice_number(year, to_string(number))

  defp to_invoice_number(year, number) when is_integer(year) and is_binary(number),
    do: "#{year}-#{String.pad_leading(number, 5, "0")}"

  project(%ExpenseRemoved{} = expense_removed, _metadata, fn multi ->
    expense = Conta.Repo.get_by(Expense, invoice_number: expense_removed.invoice_number, invoice_date: expense_removed.invoice_date)
    Ecto.Multi.delete(multi, :delete_expense, expense)
  end)

  project(%InvoiceRemoved{} = invoice_removed, _metadata, fn multi ->
    invoice_number = to_invoice_number(invoice_removed.invoice_date, invoice_removed.invoice_number)
    invoice = Conta.Repo.get_by(Invoice, invoice_number: invoice_number)
    Ecto.Multi.delete(multi, :delete_invoice, invoice)
  end)

  project(%InvoiceSet{action: :insert} = invoice, _metadata, fn multi ->
    invoice_number = to_invoice_number(invoice.invoice_date, invoice.invoice_number)

    changeset =
      invoice
      |> Map.from_struct()
      |> Map.put(:invoice_number, invoice_number)
      |> Map.update!(:subtotal_price, &to_integer/1)
      |> Map.update!(:tax_price, &to_integer/1)
      |> Map.update!(:total_price, &to_integer/1)
      |> Map.update!(:details, fn details ->
        for detail <- details do
          detail
          |> Map.from_struct()
          |> Map.update!(:base_price, &to_integer/1)
          |> Map.update!(:tax_price, &to_integer/1)
          |> Map.update!(:total_price, &to_integer/1)
        end
      end)
      |> Map.update!(:company, &Map.from_struct/1)
      |> Map.update(:payment_method, nil, &if(&1 != nil, do: Map.from_struct(&1)))
      |> Map.update(:client, nil, &if(&1 != nil, do: Map.from_struct(&1)))
      |> Invoice.changeset()

    multi
    |> Ecto.Multi.insert(:invoice, changeset)
    |> Ecto.Multi.run(:notify, fn _repo, data ->
      event_name = "event:invoice_set"
      invoice = data[:invoice]
      Logger.debug("sending broadcast for event #{inspect(event_name)}")
      case Phoenix.PubSub.broadcast(Conta.PubSub, event_name, {:invoice_set, invoice}) do
        :ok -> {:ok, nil}
        error -> error
      end
    end)
  end)

  project(%ExpenseSet{action: :insert} = expense, _metadata, fn multi ->
    changeset =
      expense
      |> Map.from_struct()
      |> Map.update!(:subtotal_price, &to_integer/1)
      |> Map.update!(:tax_price, &to_integer/1)
      |> Map.update!(:total_price, &to_integer/1)
      |> Map.update!(:company, &Map.from_struct/1)
      |> Map.update!(:attachments, fn attachments -> Enum.map(attachments, &Map.from_struct/1) end)
      |> Map.update(:payment_method, nil, &if(&1 != nil, do: Map.from_struct(&1)))
      |> Map.update(:provider, nil, &if(&1 != nil, do: Map.from_struct(&1)))
      |> Expense.changeset()

    multi
    |> Ecto.Multi.insert(:expense, changeset)
    |> Ecto.Multi.run(:notify, fn _repo, data ->
      event_name = "event:expense_set"
      expense = data[:expense]
      expense = Map.put(expense, :num_attachments, length(expense.attachments))
      Logger.debug("sending broadcast for event #{inspect(event_name)}")
      case Phoenix.PubSub.broadcast(Conta.PubSub, event_name, {:expense_set, expense}) do
        :ok -> {:ok, nil}
        error -> error
      end
    end)
  end)

  project(%InvoiceSet{action: :update} = invoice, _metadata, fn multi ->
    invoice_number = to_invoice_number(invoice.invoice_date, invoice.invoice_number)

    params =
      invoice
      |> Map.from_struct()
      |> Map.delete(:invoice_number)
      |> Map.update!(:subtotal_price, &to_integer/1)
      |> Map.update!(:tax_price, &to_integer/1)
      |> Map.update!(:total_price, &to_integer/1)
      |> Map.update!(:details, fn details ->
        for detail <- details do
          detail
          |> Map.from_struct()
          |> Map.update!(:base_price, &to_integer/1)
          |> Map.update!(:tax_price, &to_integer/1)
          |> Map.update!(:total_price, &to_integer/1)
        end
      end)
      |> Map.update!(:company, &Map.from_struct/1)
      |> Map.update(:payment_method, nil, &if(&1 != nil, do: Map.from_struct(&1)))
      |> Map.update(:client, nil, &if(&1 != nil, do: Map.from_struct(&1)))

    old_invoice = Conta.Repo.get_by!(Invoice, [invoice_number: invoice_number])

    changeset = Invoice.changeset(old_invoice, params)

    multi
    |> Ecto.Multi.update(:invoice, changeset)
    |> Ecto.Multi.run(:notify, fn _repo, data ->
      event_name = "event:invoice_set"
      invoice = data[:invoice]
      Logger.debug("sending broadcast for event #{inspect(event_name)}")
      case Phoenix.PubSub.broadcast(Conta.PubSub, event_name, {:invoice_set, invoice}) do
        :ok -> {:ok, nil}
        error -> error
      end
    end)
  end)

  project(%ExpenseSet{action: :update} = expense, _metadata, fn multi ->
    params =
      expense
      |> Map.from_struct()
      |> Map.update!(:subtotal_price, &to_integer/1)
      |> Map.update!(:tax_price, &to_integer/1)
      |> Map.update!(:total_price, &to_integer/1)
      |> Map.update!(:company, &Map.from_struct/1)
      |> Map.update!(:attachments, fn attachments -> Enum.map(attachments, &Map.from_struct/1) end)
      |> Map.update(:payment_method, nil, &if(&1 != nil, do: Map.from_struct(&1)))
      |> Map.update(:provider, nil, &if(&1 != nil, do: Map.from_struct(&1)))

    old_expense = Conta.Repo.get_by!(Expense, [invoice_number: expense.invoice_number])

    changeset = Expense.changeset(old_expense, params)

    multi
    |> Ecto.Multi.update(:expense, changeset)
    |> Ecto.Multi.run(:notify, fn _repo, data ->
      event_name = "event:expense_set"
      expense = data[:expense]
      expense = Map.put(expense, :num_attachments, length(expense.attachments))
      Logger.debug("sending broadcast for event #{inspect(event_name)}")
      case Phoenix.PubSub.broadcast(Conta.PubSub, event_name, {:expense_set, expense}) do
        :ok -> {:ok, nil}
        error -> error
      end
    end)
  end)

  project(%PaymentMethodSet{} = payment_method, _metadata, fn multi ->
    changeset =
      payment_method
      |> Map.from_struct()
      |> PaymentMethod.changeset()

    update =
      payment_method
      |> Map.from_struct()
      |> Map.drop(~w[nif slug]a)
      |> Enum.to_list()

    opts = [on_conflict: [set: update], conflict_target: [:nif, :slug]]
    Ecto.Multi.insert(multi, :template, changeset, opts)
  end)

  project(%TemplateSet{} = template, _metadata, fn multi ->
    changeset =
      template
      |> Map.from_struct()
      |> translate_logo()
      |> Template.changeset()

    update =
      template
      |> Map.from_struct()
      |> translate_logo()
      |> Map.delete(:name)
      |> Enum.to_list()

    opts = [on_conflict: [set: update], conflict_target: [:name]]
    Ecto.Multi.insert(multi, :template, changeset, opts)
  end)

  defp translate_logo(%{logo: nil} = params), do: params

  defp translate_logo(%{logo: logo} = params) do
    Map.put(params, :logo, Base.decode64!(logo))
  end
end
