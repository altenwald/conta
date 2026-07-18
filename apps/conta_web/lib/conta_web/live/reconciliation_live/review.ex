defmodule ContaWeb.ReconciliationLive.Review do
  use ContaWeb, :live_view

  require Logger

  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Command.RemoveMovement
  alias Conta.Ledger
  alias Conta.Projector.Reconciliation.Movement
  alias Conta.Reconciliation

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

  def handle_event("confirm", %{"ids" => ids_param}, socket) do
    ids = String.split(ids_param, ",", trim: true)

    {succeeded, failed} =
      ids
      |> Reconciliation.confirm_movements()
      |> Enum.reduce({[], %{}}, fn
        {id, {:ok, _}}, {succeeded, failed} -> {[id | succeeded], failed}
        {id, {:error, reason}}, {succeeded, failed} -> {succeeded, Map.put(failed, id, reason)}
      end)

    socket =
      socket
      |> assign(:movements, Enum.reject(socket.assigns.movements, &(&1.id in succeeded)))
      |> assign(:selected, MapSet.difference(socket.assigns.selected, MapSet.new(succeeded)))
      |> assign(:errors, socket.assigns.errors |> Map.drop(succeeded) |> Map.merge(failed))
      |> maybe_flash_confirm_result(failed)

    {:noreply, socket}
  end

  def handle_event("update_account", %{"id" => id, "value" => value}, socket) do
    account_name = if value in [nil, ""], do: nil, else: String.split(value, ".")
    perform_update(socket, id, %{"account_name" => account_name})
  end

  def handle_event("update_field", %{"id" => id, "field" => field, "value" => value}, socket) do
    perform_update(socket, id, %{field => value})
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
  attr :value, :any, required: true

  defp editable(assigns) do
    ~H"""
    <form phx-change="update_field" phx-value-id={@id} phx-value-field={@field} id={"#{@field}-form-#{@id}"}>
      <input type={@type} name="value" value={@value} class="input input-sm w-full" />
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
        <option value="">{gettext("(No account)")}</option>
        <option :for={name <- @accounts} value={name} selected={@value == name}>{name}</option>
      </select>
    </form>
    """
  end
end
