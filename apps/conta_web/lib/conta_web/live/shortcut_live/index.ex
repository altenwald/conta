defmodule ContaWeb.ShortcutLive.Index do
  use ContaWeb, :live_view

  require Logger

  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Automator
  alias Conta.Projector.Automator.Shortcut

  @impl true
  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(Conta.PubSub, "event:shortcut_set")
    {:ok, stream(socket, :automator_shortcuts, Automator.list_shortcuts())}
  end

  @impl true
  def handle_info({:shortcut_set, shortcut}, socket) do
    {:noreply, stream_insert(socket, :automator_shortcuts, shortcut, at: 0)}
  end

  @impl true
  def handle_event("delete", %{"id" => id, "dom_id" => dom_id}, socket) do
    with %Shortcut{} = shortcut <- Automator.get_shortcut(id),
         :ok <- dispatch(Automator.get_remove_shortcut(shortcut)) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Shortcut removed successfully"))
       |> stream_delete_by_dom_id(:automator_shortcuts, dom_id)}
    else
      error ->
        Logger.error("cannot remove shortcut: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, gettext("Cannot remove the shortcut"))}
    end
  end
end
