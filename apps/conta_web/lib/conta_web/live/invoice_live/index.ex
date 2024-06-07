defmodule ContaWeb.InvoiceLive.Index do
  use ContaWeb, :live_view

  require Logger

  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Book
  alias Conta.Projector.Book.Invoice

  @impl true
  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(Conta.PubSub, "event:invoice_set")
    {:ok, stream(socket, :books_invoices, Book.list_invoices())}
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

  @impl true
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
