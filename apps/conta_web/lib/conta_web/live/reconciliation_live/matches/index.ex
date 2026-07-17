defmodule ContaWeb.ReconciliationLive.Matches.Index do
  use ContaWeb, :live_view

  require Logger

  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Command.RemoveMatchRule
  alias Conta.Command.ReorderMatchRules
  alias Conta.Reconciliation

  @impl true
  def mount(_params, _session, socket) do
    match_rules = Reconciliation.list_match_rules()

    {:ok,
     socket
     |> assign(:match_rules, match_rules)
     |> stream(:match_rules, match_rules)}
  end

  @impl true
  def handle_event("delete", %{"id" => id, "dom_id" => dom_id}, socket) do
    case dispatch(%RemoveMatchRule{id: id}) do
      :ok ->
        {:noreply,
         socket
         |> assign(:match_rules, Enum.reject(socket.assigns.match_rules, &(&1.id == id)))
         |> put_flash(:info, gettext("Match rule removed successfully"))
         |> stream_delete_by_dom_id(:match_rules, dom_id)}

      error ->
        Logger.error("cannot remove match rule: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, gettext("Cannot remove the match rule"))}
    end
  end

  def handle_event("move_up", %{"id" => id}, socket) do
    {:noreply, reorder(socket, id, -1)}
  end

  def handle_event("move_down", %{"id" => id}, socket) do
    {:noreply, reorder(socket, id, 1)}
  end

  # `@match_rules` (kept in sync on every mutation, alongside the `:match_rules`
  # stream used for rendering) is the current display order. Moving `id` `delta`
  # places up/down (clamped to the ends, so a click on the first rule's "move up"
  # or the last rule's "move down" is a no-op rather than an error) gives the full
  # new order to send as `ReorderMatchRules.ids`.
  defp reorder(socket, id, delta) do
    ids = Enum.map(socket.assigns.match_rules, & &1.id)
    index = Enum.find_index(ids, &(&1 == id))
    new_index = index && index + delta

    if index && new_index >= 0 and new_index < length(ids) do
      new_ids = ids |> List.delete_at(index) |> List.insert_at(new_index, id)
      apply_reorder(socket, new_ids)
    else
      socket
    end
  end

  # Reorders the already-known-in-memory rules to match `new_ids` rather than
  # re-querying `Reconciliation.list_match_rules/0` after dispatch: the projector
  # that writes `position` to the read model runs asynchronously (this app's
  # command dispatch defaults to `consistency: :eventual`, see
  # `Conta.Commanded.Router`), so an immediate re-query here could race it and
  # briefly show the pre-reorder order. Dispatching still gives us the
  # authoritative persisted order for the *next* page load; this just avoids
  # flickering/racing the current one.
  defp apply_reorder(socket, new_ids) do
    case dispatch(%ReorderMatchRules{ids: new_ids}) do
      :ok ->
        by_id = Map.new(socket.assigns.match_rules, &{&1.id, &1})
        new_match_rules = Enum.map(new_ids, &by_id[&1])

        socket
        |> assign(:match_rules, new_match_rules)
        |> stream(:match_rules, new_match_rules, reset: true)

      error ->
        Logger.error("cannot reorder match rules: #{inspect(error)}")
        put_flash(socket, :error, gettext("Cannot reorder the match rules"))
    end
  end
end
