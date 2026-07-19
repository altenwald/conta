defmodule ContaWeb.ImporterLive.Index do
  use ContaWeb, :live_view

  require Logger

  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Automator
  alias Conta.Projector.Automator.Importer

  @impl true
  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(Conta.PubSub, "event:importer_set")
    {:ok, stream(socket, :automator_importers, Automator.list_importers())}
  end

  @impl true
  def handle_info({:importer_set, importer}, socket) do
    {:noreply, stream_insert(socket, :automator_importers, importer, at: 0)}
  end

  @impl true
  def handle_event("delete", %{"id" => id, "dom_id" => dom_id}, socket) do
    with %Importer{} = importer <- Automator.get_importer(id),
         :ok <- dispatch(Automator.get_remove_importer(importer)) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Importer removed successfully"))
       |> stream_delete_by_dom_id(:automator_importers, dom_id)}
    else
      error ->
        Logger.error("cannot remove importer: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, gettext("Cannot remove the importer"))}
    end
  end
end
