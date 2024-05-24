defmodule ContaWeb.EntryLive.Index do
  use ContaWeb, :live_view

  alias Conta.Ledger
  alias ContaWeb.EntryLive.FormComponent.AccountTransaction

  @impl true
  def mount(%{"account_id" => account_id}, _session, socket) do
    account = Ledger.get_account!(account_id)

    {:ok,
     socket
     |> stream(:ledger_entries, list_entries_by_account(account))
     |> assign(:account, account)}
  end

  defp list_entries_by_account(account) do
    account
    |> Ledger.list_entries_by_account()
    |> Enum.group_by(& &1.on_date)
    |> Enum.map(fn {on_date, entries} -> %{id: on_date, title: on_date, rows: entries} end)
    |> Enum.sort_by(& &1.title, {:desc, Date})
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
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
    {:noreply, stream(socket, :ledger_entries, list_entries_by_account(account))}
  end

  defp description(text) when is_binary(text) and byte_size(text) < 15, do: text
  defp description(text), do: String.slice(text, 0..12) <> "..."

  defp account_name(nil), do: gettext("-- Breakdown")
  defp account_name(name) when is_list(name), do: Enum.join(name, ".")
  defp account_name(name) when is_binary(name), do: name
  defp account_name(%{name: name}) when is_list(name), do: Enum.join(name, ".")
end
