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
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:entry, Ledger.get_entry!(id))}
  end

  defp page_title(:show), do: gettext("Show Entry")
  defp page_title(:edit), do: gettext("Edit Entry")
end
