defmodule ContaWeb.AccountLive.Show do
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
     |> assign(:set_account, Ledger.get_account_command!(id))
     |> assign(:account, Ledger.get_account!(id))
     |> assign(:subaccounts, Ledger.get_account_by_parent_id(id))}
  end

  defp get_currency(currency) do
    Money.Currency.name(currency) <>
      " (" <> Money.Currency.symbol(currency) <> ")"
  end

  defp page_title(:show), do: gettext("Show Account")
  defp page_title(:edit), do: gettext("Edit Account")
end
