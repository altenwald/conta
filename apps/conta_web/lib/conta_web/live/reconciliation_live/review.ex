defmodule ContaWeb.ReconciliationLive.Review do
  use ContaWeb, :live_view

  require Logger

  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Command.RemoveMovement
  alias Conta.Ledger
  alias Conta.Projector.Reconciliation.Movement
  alias Conta.Reconciliation

  # The exact set of fields the template's `<.editable>` component ever submits
  # through the `update_field` event. Kept as an allowlist so a forged/unexpected
  # `field` param can't be forwarded straight into `Reconciliation.update_movement/2`.
  @editable_fields ~w(on_date description amount)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Review pending movements"))
     |> assign(:movements, Reconciliation.list_movements())
     |> assign(:accounts, account_options())
     |> assign(:selected, MapSet.new())
     |> assign(:errors, %{})}
  end

  @impl true
  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected, id) do
        MapSet.delete(socket.assigns.selected, id)
      else
        MapSet.put(socket.assigns.selected, id)
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("select_all", _params, socket) do
    selected = MapSet.new(selectable_ids(socket.assigns.movements))
    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("deselect_all", _params, socket) do
    {:noreply, assign(socket, :selected, MapSet.new())}
  end

  def handle_event("invert_selection", _params, socket) do
    selectable = MapSet.new(selectable_ids(socket.assigns.movements))
    selected = MapSet.symmetric_difference(selectable, socket.assigns.selected)
    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("remove_selected", %{"ids" => ids_param}, socket) do
    ids = String.split(ids_param, ",", trim: true)

    {succeeded, failed} =
      Enum.reduce(ids, {MapSet.new(), %{}}, fn id, {succeeded, failed} ->
        case dispatch(%RemoveMovement{id: id}) do
          :ok -> {MapSet.put(succeeded, id), failed}
          {:error, reason} -> {succeeded, Map.put(failed, id, reason)}
        end
      end)

    socket =
      socket
      |> assign(:movements, Enum.reject(socket.assigns.movements, &(&1.id in succeeded)))
      |> assign(:selected, MapSet.difference(socket.assigns.selected, succeeded))
      |> assign(:errors, socket.assigns.errors |> Map.drop(MapSet.to_list(succeeded)) |> Map.merge(failed))
      |> maybe_flash_remove_result(failed)

    {:noreply, socket}
  end

  def handle_event("confirm", %{"ids" => ids_param}, socket) do
    ids = String.split(ids_param, ",", trim: true)

    {succeeded, failed} =
      ids
      |> Reconciliation.confirm_movements()
      |> Enum.reduce({MapSet.new(), %{}}, fn
        {id, {:ok, _}}, {succeeded, failed} -> {MapSet.put(succeeded, id), failed}
        {id, {:error, reason}}, {succeeded, failed} -> {succeeded, Map.put(failed, id, reason)}
      end)

    socket =
      socket
      |> assign(:movements, Enum.reject(socket.assigns.movements, &(&1.id in succeeded)))
      |> assign(:selected, MapSet.difference(socket.assigns.selected, succeeded))
      |> assign(:errors, socket.assigns.errors |> Map.drop(MapSet.to_list(succeeded)) |> Map.merge(failed))
      |> mark_drifted_transacted(failed)
      |> maybe_flash_confirm_result(failed)

    {:noreply, socket}
  end

  # There is no UI path for unassigning an account back to nil (see
  # `account_select/1`'s disabled placeholder option below) — every value this
  # handler receives is a real, existing account name.
  def handle_event("update_account", %{"id" => id, "value" => value}, socket) when value != "" do
    perform_update(socket, id, %{"account_name" => String.split(value, ".")})
  end

  def handle_event("update_account", %{"value" => ""}, socket) do
    {:noreply, socket}
  end

  def handle_event("update_field", %{"id" => id, "field" => field, "value" => value}, socket)
      when field in @editable_fields do
    perform_update(socket, id, %{field => value})
  end

  def handle_event("update_field", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("remove", %{"id" => id}, socket) do
    movement = Enum.find(socket.assigns.movements, &(&1.id == id))

    result =
      if movement && movement.transacted do
        Reconciliation.confirm_movement(id)
      else
        dispatch(%RemoveMovement{id: id})
      end

    case result do
      :ok ->
        {:noreply, remove_locally(socket, id)}

      {:ok, _} ->
        {:noreply, remove_locally(socket, id)}

      {:error, reason} ->
        Logger.error("cannot remove movement #{id}: #{inspect(reason)}")
        {:noreply, put_error(socket, id, reason)}
    end
  end

  defp maybe_flash_confirm_result(socket, failed) when map_size(failed) == 0 do
    put_flash(socket, :info, gettext("Selected movements confirmed successfully"))
  end

  defp maybe_flash_confirm_result(socket, _failed) do
    put_flash(socket, :error, gettext("Some movements could not be confirmed"))
  end

  defp maybe_flash_remove_result(socket, failed) when map_size(failed) == 0 do
    put_flash(socket, :info, gettext("Selected movements removed successfully"))
  end

  defp maybe_flash_remove_result(socket, _failed) do
    put_flash(socket, :error, gettext("Some movements could not be removed"))
  end

  # The only movements a checkbox ever renders for (see the `top` table in
  # review.html.heex) - transacted rows and accountless rows don't get one, so
  # "select all"/"invert selection" must match that same set or they'd select
  # ids with no checkbox to represent them.
  defp selectable_ids(movements) do
    for movement <- movements, movement.account_name, not movement.transacted, do: movement.id
  end

  # `Reconciliation.confirm_movement/1` documents a residual risk: `SetAccountTransaction`
  # + `MarkMovementTransacted` can both succeed while the trailing `RemoveMovement` fails,
  # so the id still comes back in `failed` even though the read model now genuinely has
  # `transacted: true`. The failure reason alone can't cleanly distinguish this from
  # "no account assigned"/"zero amount"/etc, so re-check the read model directly for each
  # failed id and, if it has already flipped to `transacted: true`, mirror that locally so
  # the row renders with the "pending cleanup" treatment instead of as an ordinary row.
  defp mark_drifted_transacted(socket, failed) do
    assign(socket, :movements, Enum.map(socket.assigns.movements, &maybe_mark_transacted(&1, failed)))
  end

  defp maybe_mark_transacted(%{id: id, transacted: false} = movement, failed) do
    if Map.has_key?(failed, id) and transacted_in_read_model?(id) do
      %{movement | transacted: true}
    else
      movement
    end
  end

  defp maybe_mark_transacted(movement, _failed), do: movement

  defp transacted_in_read_model?(id) do
    case Reconciliation.get_movement!(id) do
      %{transacted: true} -> true
      _ -> false
    end
  rescue
    Ecto.NoResultsError -> false
  end

  defp perform_update(socket, id, changes) do
    case Reconciliation.update_movement(id, changes) do
      :ok ->
        {:noreply, apply_local_update(socket, id, changes)}

      {:error, reason} ->
        Logger.error("cannot update movement #{id}: #{inspect(reason)}")
        {:noreply, put_error(socket, id, reason)}
    end
  end

  # Applies `changes` to the in-memory movement (using the same
  # `Movement.changeset/2` casting rules as the projector) instead of
  # re-querying `Reconciliation.list_movements/0` right after dispatch. The
  # projector that writes this app's read model runs asynchronously (this
  # app's command dispatch defaults to `consistency: :eventual`, and
  # `:consistency` isn't actually propagated to any projector regardless of
  # what's requested — see TODO.md), so an immediate re-query here could race
  # it and briefly show stale data (or, worse, momentarily "lose" the account
  # just assigned). This mirrors the same reasoning `Matches.Index.reorder/3`
  # already uses for the identical race in this codebase.
  defp apply_local_update(socket, id, changes) do
    movements =
      Enum.map(socket.assigns.movements, fn
        %{id: ^id} = movement -> cast_movement(movement, changes)
        movement -> movement
      end)

    socket
    |> assign(:movements, movements)
    |> assign(:errors, Map.delete(socket.assigns.errors, id))
  end

  defp cast_movement(movement, changes) do
    movement
    |> Movement.changeset(changes)
    |> Ecto.Changeset.apply_action(:update)
    |> case do
      {:ok, updated} -> updated
      {:error, _changeset} -> movement
    end
  end

  defp remove_locally(socket, id) do
    socket
    |> assign(:movements, Enum.reject(socket.assigns.movements, &(&1.id == id)))
    |> assign(:selected, MapSet.delete(socket.assigns.selected, id))
    |> assign(:errors, Map.delete(socket.assigns.errors, id))
  end

  defp put_error(socket, id, reason) do
    assign(socket, :errors, Map.put(socket.assigns.errors, id, reason))
  end

  defp account_options do
    for account <- Ledger.list_accounts(), do: Enum.join(account.name, ".")
  end

  @doc false
  def format_error(:no_account_assigned), do: gettext("No account assigned")
  def format_error(:zero_amount), do: gettext("Amount is zero")
  def format_error(:not_found), do: gettext("Movement not found")
  def format_error(reason), do: inspect(reason)

  attr :id, :string, required: true
  attr :field, :string, required: true
  attr :type, :string, default: "text"
  attr :step, :string, default: nil
  attr :value, :any, required: true

  defp editable(assigns) do
    ~H"""
    <form phx-change="update_field" phx-value-id={@id} phx-value-field={@field} id={"#{@field}-form-#{@id}"}>
      <input type={@type} step={@step} name="value" value={@value} class="input input-sm w-full" />
    </form>
    """
  end

  attr :id, :string, required: true
  attr :value, :any, default: nil
  attr :accounts, :list, required: true

  defp account_select(assigns) do
    ~H"""
    <form phx-change="update_account" phx-value-id={@id} id={"account-form-#{@id}"}>
      <select name="value" class="select select-sm w-full">
        <option value="" selected={is_nil(@value)} disabled>{gettext("Select an account")}</option>
        <option :for={name <- @accounts} value={name} selected={@value == name}>{name}</option>
      </select>
    </form>
    """
  end
end
