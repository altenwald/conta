defmodule ContaWeb.AccountLive.Index do
  use ContaWeb, :live_view
  require Logger

  alias Conta.Command.SetAccount
  alias Conta.Ledger

  @impl true
  def mount(_params, _session, socket) do
    ledger = "default"
    Phoenix.PubSub.subscribe(Conta.PubSub, "event:account_created:#{ledger}")
    Phoenix.PubSub.subscribe(Conta.PubSub, "event:account_modified:#{ledger}")
    Phoenix.PubSub.subscribe(Conta.PubSub, "event:account_removed:#{ledger}")
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

  @impl true
  def handle_info(%{id: _}, socket) do
    {:noreply, stream(socket, :ledger_accounts, Ledger.list_accounts(), reset: true)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    account = Ledger.get_account!(id)

    case Ledger.delete_account(account.name) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Account deleted successfully"))
         |> stream(:ledger_accounts, Ledger.list_accounts(), reset: true)}

      {:error, reason} ->
        Logger.warning("cannot remove account #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, gettext("Cannot remove account"))}
    end
  end

  defp get_balance(%_{currency: currency, balances: balances}) do
    balances = Enum.group_by(balances, & &1.currency, & &1.amount.amount)

    case balances[currency] do
      [money] -> to_string(Money.new(money, currency))
      nil -> to_string(Money.new(0, currency))
    end
  end

  defp get_other_balances(%_{currency: currency, balances: balances}) do
    balances = Enum.group_by(balances, & &1.currency, & &1.amount.amount)

    for {balance_currency, [amount]} <- balances, balance_currency != currency, amount != 0 do
      to_string(Money.new(amount, balance_currency))
    end
  end
end
