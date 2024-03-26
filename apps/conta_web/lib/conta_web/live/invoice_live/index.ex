defmodule ContaWeb.InvoiceLive.Index do
  use ContaWeb, :live_view

  alias Conta.Book
  alias Conta.Command.CreateInvoice
  alias Conta.Projector.Book.Invoice

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :books_invoices, Book.list_invoices())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Invoice")
    |> assign(:invoice, Book.get_invoice_command!(id))
  end

  defp apply_action(socket, :new, _params) do
    create_invoice = Book.new_create_invoice()

    socket
    |> assign(:page_title, "New Invoice")
    |> assign(:invoice_number, create_invoice.invoice_number)
    |> assign(:create_invoice, create_invoice)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Books invoices")
    |> assign(:create_invoice, nil)
  end

  @impl true
  def handle_info({ContaWeb.InvoiceLive.FormComponent, {:saved, invoice}}, socket) do
    {:noreply, stream_insert(socket, :books_invoices, invoice)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    invoice = Book.get_invoice!(id)
    {:ok, _} = Book.delete_invoice(invoice)

    {:noreply, stream_delete(socket, :books_invoices, invoice)}
  end
end
