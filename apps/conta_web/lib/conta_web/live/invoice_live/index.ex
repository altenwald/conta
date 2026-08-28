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
     |> assign(:filters, list_filters())
     |> assign(:term_and_year, "")
     |> assign(:invoice_status, "")
     |> assign(:selected_invoice_ids, MapSet.new())
     |> assign(:email_invoices, [])}
  end

  defp list_filters do
    for filter <- Automator.list_filters_by_type(:invoice),
        do: {filter.description || filter.name, filter.id}
  end

  defp get_client(%_{client: nil, destination_country: country}) do
    gettext("Customer from %{country}", country: Countries.get(country).name)
  end

  defp get_client(%_{client: client}), do: client.name

  defp get_credit_note(%Invoice{is_credit_note: true}), do: nil

  defp get_credit_note(%Invoice{id: id}) do
    Book.get_credit_note_by_origin_invoice_id(id)
  end

  defp invoice_statuses do
    [
      {gettext("Paid"), "paid"},
      {gettext("Unpaid"), "unpaid"}
    ]
  end

  defp terms_and_years do
    case Book.get_invoice_date_range() do
      {%Date{} = max_date, %Date{} = min_date} ->
        build_terms_and_years(min_date, max_date)

      _ ->
        []
    end
  end

  defp build_terms_and_years(min_date, max_date) do
    Stream.unfold(min_date, fn date ->
      if Date.compare(date, max_date) != :gt do
        term = "Q#{div(date.month - 1, 3) + 1}"
        {"#{date.year} #{term}", Date.add(date, 1)}
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

  defp apply_action(socket, :send_email, %{"id" => id}) do
    invoice = Book.get_invoice!(id)

    socket
    |> assign(:page_title, gettext("Send Invoice by Email"))
    |> assign(:email_invoices, [invoice])
  end

  defp apply_action(socket, :send_batch_email, _params) do
    selected_ids = socket.assigns.selected_invoice_ids

    if MapSet.size(selected_ids) > 0 do
      invoices = Enum.map(selected_ids, &Book.get_invoice!/1)

      if same_client?(invoices) do
        socket
        |> assign(:page_title, gettext("Send Invoices by Email"))
        |> assign(:email_invoices, invoices)
      else
        socket
        |> put_flash(:error, gettext("All selected invoices must belong to the same client."))
        |> push_patch(to: ~p"/books/invoices")
      end
    else
      push_patch(socket, to: ~p"/books/invoices")
    end
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Books invoices")
    |> assign(:set_invoice, nil)
    |> assign(:email_invoices, [])
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

  def handle_event("create_credit_note", %{"id" => invoice_id}, socket) do
    with %Invoice{} = invoice <- Book.get_invoice(invoice_id),
         {:ok, _command} <- Book.create_credit_note_from_invoice(invoice) do
      {:noreply, put_flash(socket, :info, gettext("Credit note created successfully"))}
    else
      {:error, reason} ->
        Logger.error("cannot create credit note: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, gettext("Cannot create credit note"))}

      nil ->
        {:noreply, put_flash(socket, :error, gettext("Invoice not found"))}
    end
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

  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected = socket.assigns.selected_invoice_ids

    new_selected =
      if MapSet.member?(selected, id) do
        MapSet.delete(selected, id)
      else
        MapSet.put(selected, id)
      end

    {:noreply, assign(socket, :selected_invoice_ids, new_selected)}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, :selected_invoice_ids, MapSet.new())}
  end

  def same_client?([first | rest]) do
    first_client = client_identifier(first)
    Enum.all?(rest, fn inv -> client_identifier(inv) == first_client end)
  end

  def same_client?([]), do: false

  defp client_identifier(%Invoice{client: %{nif: nif}}) when is_binary(nif) and nif != "", do: {:nif, nif}

  defp client_identifier(%Invoice{client: %{name: name}}) when is_binary(name) and name != "",
    do: {:name, name}

  defp client_identifier(%Invoice{destination_country: country}), do: {:country, country}
  defp client_identifier(_), do: :unknown

  def batch_send_status(selected_ids) do
    count = MapSet.size(selected_ids)

    if count > 0 do
      invoices =
        selected_ids
        |> Enum.map(&Book.get_invoice/1)
        |> Enum.reject(&is_nil/1)

      if length(invoices) == count and same_client?(invoices) do
        {:ok, count}
      else
        {:different_clients, count}
      end
    else
      :none
    end
  end

  @impl true
  def handle_info({:invoice_set, invoice}, socket) do
    Logger.debug("adding invoice to the stream #{invoice.invoice_number}")
    {:noreply, stream_insert(socket, :books_invoices, invoice, at: 0)}
  end

  def handle_info({:email, _email}, socket) do
    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end
end
