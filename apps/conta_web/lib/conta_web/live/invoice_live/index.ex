defmodule ContaWeb.InvoiceLive.Index do
  use ContaWeb, :live_view

  require Logger

  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Automator
  alias Conta.Book
  alias Conta.Projector.Book.Invoice

  @impl true
  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(Conta.PubSub, "event:invoice_set")

    {:ok,
     socket
     |> stream(:books_invoices, Book.list_invoices())
     |> assign(:filter, "")
     |> assign(:term_and_year, "")
     |> assign(:invoice_status, "")}
  end

  defp filters do
    for filter <- Automator.list_filters(), do: {filter.description || filter.name, filter.id}
  end

  defp invoice_statuses do
    [
      {gettext("Paid"), "paid"},
      {gettext("Unpaid"), "unpaid"}
    ]
  end

  defp terms_and_years do
    {max_date, min_date} = Book.get_date_range()

    Stream.unfold(min_date, fn date ->
      if Date.compare(date, max_date) != :gt do
        year = date.year
        term = "Q#{div(date.month - 1, 3) + 1}"
        {"#{year} #{term}", Date.add(date, 15)}
      end
    end)
    |> Enum.uniq()
    |> Enum.reverse()
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    set_invoice = Book.get_set_invoice(id)

    socket
    |> assign(:page_title, gettext("Edit Invoice"))
    |> assign(:invoice_number, set_invoice.invoice_number)
    |> assign(:company_nif, set_invoice.nif)
    |> assign(:set_invoice, set_invoice)
  end

  defp apply_action(socket, :duplicate, %{"id" => id}) do
    set_invoice = Book.get_duplicate_invoice(id)

    socket
    |> assign(:page_title, gettext("New Invoice"))
    |> assign(:invoice_number, set_invoice.invoice_number)
    |> assign(:company_nif, set_invoice.nif)
    |> assign(:set_invoice, set_invoice)
  end

  defp apply_action(socket, :new, _params) do
    set_invoice = Book.new_set_invoice()

    socket
    |> assign(:page_title, gettext("New Invoice"))
    |> assign(:invoice_number, set_invoice.invoice_number)
    |> assign(:company_nif, set_invoice.nif)
    |> assign(:set_invoice, set_invoice)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Books invoices")
    |> assign(:set_invoice, nil)
  end

  defp filters(assigns) do
    get_filters(%{
      "term-and-year" => assigns.term_and_year,
      "status" => assigns.status,
      "filter" => assigns.filter
    })
  end

  defp get_term_and_year(""), do: []
  defp get_term_and_year(nil), do: []

  defp get_term_and_year(term_and_year) do
    case String.split(term_and_year, " ") do
      [year, term] -> [term: term, year: year]
      _ -> []
    end
  end

  defp get_invoice_status(""), do: []
  defp get_invoice_status(nil), do: []
  defp get_invoice_status(value), do: [status: value]

  defp get_filters(params) do
    get_term_and_year(params["term-and-year"]) ++ get_invoice_status(params["status"])
  end

  @impl true
  def handle_event("filters", params, socket) do
    filters = get_filters(params)

    {:noreply,
     socket
     |> stream(:books_invoices, Book.list_invoices_filtered(filters), reset: true)
     |> assign(
       term_and_year: params["term-and-year"],
       status: params["status"],
       filter: params["filter"]
     )}
  end

  def handle_event("delete", %{"id" => invoice_id, "dom_id" => dom_id}, socket) do
    with %Invoice{} = invoice <- Book.get_invoice(invoice_id),
         :ok <- dispatch(Book.get_remove_invoice(invoice)) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Invoice removed successfully"))
       |> stream_delete_by_dom_id(:books_invoices, dom_id)}
    else
      error ->
        Logger.error("cannot remove: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, gettext("Cannot remove the invoice"))}
    end
  end

  @impl true
  def handle_info({:invoice_set, invoice}, socket) do
    Logger.debug("adding invoice to the stream #{invoice.invoice_number}")
    {:noreply, stream_insert(socket, :books_invoices, invoice, at: 0)}
  end
end
