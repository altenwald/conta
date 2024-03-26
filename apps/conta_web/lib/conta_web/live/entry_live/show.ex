defmodule ContaWeb.EntryLive.Show do
  use ContaWeb, :live_view

  alias Conta.Ledger

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:entry, Ledger.get_entry!(id))}
  end

  defp page_title(:show), do: "Show Entry"
  defp page_title(:edit), do: "Edit Entry"
end
