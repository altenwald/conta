defmodule ContaWeb.AccountLive.Index do
  use ContaWeb, :live_view

  alias Conta.Ledger
  alias Conta.Command.SetAccount

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :ledger_accounts, Ledger.list_accounts())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, gettext("Edit Account"))
    |> assign(:account, Ledger.get_account_command!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, gettext("New Account"))
    |> assign(:account, %SetAccount{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, gettext("Listing Ledger accounts"))
    |> assign(:account, nil)
  end

  # @impl true
  # def handle_info({ContaWeb.AccountLive.FormComponent, {:saved, account}}, socket) do
  #   {:noreply, stream_insert(socket, :ledger_accounts, account)}
  # end

  # @impl true
  # def handle_event("delete", %{"account_name" => account_name}, socket) do
  #   ## FIXME delete command
  #   {:noreply, stream_delete(socket, :ledger_accounts, account)}
  # end

  defp get_balance(%_{currency: currency, balances: balances}) do
    balances = Enum.group_by(balances, & &1.currency, & &1.amount.amount)

    case balances[currency] do
      [money] -> to_string(Money.new(money, currency))
      nil -> to_string(Money.new(0, currency))
    end
  end
end
