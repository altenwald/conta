defmodule ContaWeb.EntryLive.Index do
  use ContaWeb, :live_view

  alias Conta.Ledger
  alias Conta.Projector.Ledger.Entry

  @impl true
  def mount(%{"account_id" => account_id}, _session, socket) do
    account = Ledger.get_account!(account_id)

    {:ok,
     socket
     |> stream(:ledger_entries, Ledger.list_entries_by_account(account))
     |> assign(:account, account)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Entry")
    |> assign(:entry, Ledger.get_entry!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Entry")
    |> assign(:entry, %Entry{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Ledger entries")
    |> assign(:entry, nil)
  end

  @impl true
  def handle_info({ContaWeb.EntryLive.FormComponent, {:saved, entry}}, socket) do
    {:noreply, stream_insert(socket, :ledger_entries, entry)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    entry = Ledger.get_entry!(id)
    {:ok, _} = Ledger.delete_entry(entry)

    {:noreply, stream_delete(socket, :ledger_entries, entry)}
  end

  defp description(text) when is_binary(text) and byte_size(text) < 15, do: text
  defp description(text), do: String.slice(text, 0..12) <> "..."

  defp account_name(nil), do: gettext("-- Breakdown")
  defp account_name(name) when is_list(name), do: Enum.join(name, ".")
  defp account_name(name) when is_binary(name), do: name
  defp account_name(%{name: name}) when is_list(name), do: Enum.join(name, ".")
end
