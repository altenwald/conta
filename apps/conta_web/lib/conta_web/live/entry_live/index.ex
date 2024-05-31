defmodule ContaWeb.EntryLive.Index do
  use ContaWeb, :live_view

  alias Conta.Ledger
  alias ContaWeb.EntryLive.FormComponent.AccountTransaction

  @dates_per_page 5

  @impl true
  def mount(%{"account_id" => account_id}, _session, socket) do
    account = Ledger.get_account!(account_id)

    {:ok,
     socket
     |> assign(account: account, page: 1)
     |> paginate_entries(1, @dates_per_page)}
  end

  defp flat_title_and_entries(entries, on_date \\ nil, acc \\ [])

  defp flat_title_and_entries([], _on_date, rows), do: Enum.reverse(rows)

  defp flat_title_and_entries([%_{on_date: on_date} = entry | entries], on_date, rows) do
    row = %{id: entry.id, title: nil, row: entry}
    flat_title_and_entries(entries, on_date, [row | rows])
  end

  defp flat_title_and_entries([%_{on_date: on_date} | _] = entries, _on_date, rows) do
    row = %{id: on_date, title: on_date, row: nil}
    flat_title_and_entries(entries, on_date, [row | rows])
  end

  defp paginate_entries(socket, new_page, _dates_per_page)
       when not is_integer(new_page) or new_page <= 0,
       do: socket

  defp paginate_entries(socket, new_page, dates_per_page) do
    %{page: cur_page, account: account} = socket.assigns

    entries =
      account
      |> Ledger.list_entries_by_account(new_page, dates_per_page)
      |> flat_title_and_entries()

    {entries, at} =
      if new_page >= cur_page do
        {entries, -1}
      else
        {Enum.reverse(entries), 0}
      end

    if match?([_ | _], entries) do
      socket
      |> assign(:page, new_page)
      |> stream(:ledger_entries, entries, at: at)
    else
      socket
    end
  end

  @impl true
  def handle_event("next-page", %{}, socket) do
    {:noreply, paginate_entries(socket, socket.assigns.page + 1, @dates_per_page)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :duplicate, %{"id" => transaction_id}) do
    entries = Ledger.get_entries_by_transaction_id(transaction_id)
    account_transaction = AccountTransaction.edit(entries)

    socket
    |> assign(:page_title, gettext("New Entry"))
    |> assign(:transaction_id, Ecto.UUID.generate())
    |> assign(:account_transaction, account_transaction)
    |> assign(:breakdown, account_transaction.breakdown)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, gettext("New Entry"))
    |> assign(:transaction_id, Ecto.UUID.generate())
    |> assign(:account_transaction, %AccountTransaction{})
    |> assign(:breakdown, false)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, gettext("Listing Ledger entries"))
    |> assign(:transaction_id, nil)
    |> assign(:account_transaction, nil)
  end

  @impl true
  def handle_info({ContaWeb.EntryLive.FormComponent, {:saved, _entry}}, socket) do
    account = socket.assigns.account
    {:noreply, redirect(socket, to: ~p"/ledger/accounts/#{account}/entries")}
  end

  defp description(text) when is_binary(text) and byte_size(text) < 15, do: text
  defp description(text), do: String.slice(text, 0..12) <> "..."

  defp account_name(nil), do: gettext("-- Breakdown")
  defp account_name(name) when is_list(name), do: Enum.join(name, ".")
  defp account_name(name) when is_binary(name), do: name
  defp account_name(%{name: name}) when is_list(name), do: Enum.join(name, ".")
end
