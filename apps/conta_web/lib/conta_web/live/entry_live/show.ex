defmodule ContaWeb.EntryLive.Show do
  use ContaWeb, :live_view

  alias Conta.Ledger

  @impl true
  def mount(%{"account_id" => account_id}, _session, socket) do
    account = Ledger.get_account!(account_id)
    {:ok, assign(socket, :account, account)}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    entry = Ledger.get_entry!(id)
    account = socket.assigns.account

    account_transaction =
      entry.transaction_id
      |> Ledger.get_entries_by_transaction_id()
      |> ContaWeb.EntryLive.Index.first_entry_with_account_name(account.name)
      |> ContaWeb.EntryLive.FormComponent.AccountTransaction.edit()

    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:entry, entry)
     |> assign(:account_transaction, account_transaction)
     |> assign(:breakdown, account_transaction.breakdown)
     |> assign(:transaction_id, account_transaction.transaction_id)}
  end

  defp page_title(:show), do: gettext("Show Entry")
  defp page_title(:edit), do: gettext("Edit Entry")

  @impl true
  def handle_info({:account_selected, _id, _account}, socket) do
    {:noreply, socket}
  end
end
