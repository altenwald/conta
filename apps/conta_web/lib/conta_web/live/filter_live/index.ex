defmodule ContaWeb.FilterLive.Index do
  use ContaWeb, :live_view

  require Logger

  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Automator
  alias Conta.Projector.Automator.Filter

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :automator_filters, Automator.list_filters())}
  end

  @impl true
  def handle_event("delete", %{"id" => id, "dom_id" => dom_id}, socket) do
    with %Filter{} = filter <- Automator.get_filter(id),
         :ok <- dispatch(Automator.get_remove_filter(filter)) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Filter removed successfully"))
       |> stream_delete_by_dom_id(:automator_filters, dom_id)}
    else
      error ->
        Logger.error("cannot remove filter: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, gettext("Cannot remove the filter"))}
    end
  end
end
