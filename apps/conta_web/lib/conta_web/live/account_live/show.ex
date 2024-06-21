defmodule ContaWeb.AccountLive.Show do
  use ContaWeb, :live_view

  alias Conta.Ledger

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    if Regex.match?(~r/^[0-9a-f-]{36}$/, id) do
      {:noreply,
       socket
       |> assign(:page_title, page_title(socket.assigns.live_action))
       |> assign(:set_account, Ledger.get_account_command!(id))
       |> assign(:account, Ledger.get_account!(id))
       |> assign(:subaccounts, Ledger.get_account_by_parent_id(id))}
    else
      name = String.split(id, ".")

      case Ledger.get_account_by_name(name) do
        {:ok, account} ->
          {:noreply, redirect(socket, to: ~p"/ledger/accounts/#{account}")}

        {:error, _reason} ->
          {:noreply,
           socket
           |> put_flash(:error, gettext("Account not found"))
           |> redirect(to: ~p"/ledger/accounts")}
      end
    end
  end

  defp get_currency(currency) do
    Money.Currency.name(currency) <>
      " (" <> Money.Currency.symbol(currency) <> ")"
  end

  defp page_title(:show), do: gettext("Show Account")
  defp page_title(:edit), do: gettext("Edit Account")
end
