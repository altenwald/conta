defmodule ContaWeb.ReconciliationLive.Matches.Form do
  use ContaWeb, :live_view

  import Ecto.Changeset, only: [get_field: 2]
  import Conta.Commanded.Application, only: [dispatch: 1]

  require Logger

  alias Conta.Command.SetMatchRule
  alias Conta.Ledger
  alias Conta.Reconciliation

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :accounts, Ledger.list_simple_accounts())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    set_match_rule = Reconciliation.new_set_match_rule()

    socket
    |> assign(:page_title, gettext("New match rule"))
    |> assign(:set_match_rule, set_match_rule)
    |> assign(:form_params, %{})
    |> assign_form(SetMatchRule.changeset(set_match_rule, %{}))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    set_match_rule = Reconciliation.get_set_match_rule(id)
    changeset = SetMatchRule.changeset(set_match_rule, %{})

    socket
    |> assign(:page_title, gettext("Edit match rule"))
    |> assign(:set_match_rule, set_match_rule)
    |> assign(:form_params, %{
      "conditions" => conditions_to_form_params(get_field(changeset, :conditions) || [])
    })
    |> assign_form(changeset)
  end

  @impl true
  def handle_event("validate", %{"set_match_rule" => params}, socket) do
    changeset =
      socket.assigns.set_match_rule
      |> SetMatchRule.changeset(force_params(params))
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:form_params, params) |> assign_form(changeset)}
  end

  def handle_event("add_condition", _params, socket) do
    params =
      Map.update(socket.assigns.form_params, "conditions", %{"0" => %{}}, fn existing ->
        Map.put(existing, to_string(map_size(existing)), %{})
      end)

    changeset =
      socket.assigns.set_match_rule
      |> SetMatchRule.changeset(force_params(params))
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:form_params, params) |> assign_form(changeset)}
  end

  def handle_event("del_condition", %{"index" => index}, socket) do
    params = Map.update(socket.assigns.form_params, "conditions", %{}, &Map.delete(&1, index))

    changeset =
      socket.assigns.set_match_rule
      |> SetMatchRule.changeset(force_params(params))
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:form_params, params) |> assign_form(changeset)}
  end

  def handle_event("save", %{"set_match_rule" => params}, socket) do
    changeset = SetMatchRule.changeset(socket.assigns.set_match_rule, force_params(params))

    if changeset.valid? and dispatch(SetMatchRule.to_command(changeset)) == :ok do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Match rule saved successfully"))
       |> push_navigate(to: ~p"/ledger/reconciliation/matches")}
    else
      Logger.debug("changeset errors: #{inspect(changeset.errors)}")

      {:noreply,
       socket
       |> assign(:form_params, params)
       |> assign_form(Map.put(changeset, :action, :validate))}
    end
  end

  # Seeds :form_params with the rule's existing conditions on first load, in the
  # same shape a form submission would produce. Without this, add_condition and
  # del_condition - which only ever see phx-click, never the form's own fields -
  # build their next state from an empty map on the first click of an edit
  # session, wiping out every existing condition but the fresh one they add.
  # Mirrors `ContaWeb.ShortcutLive.Form`'s `params_to_form_params/1`.
  defp conditions_to_form_params(conditions) do
    conditions
    |> Enum.with_index()
    |> Map.new(fn {condition, idx} ->
      {to_string(idx),
       %{
         "field" => to_string(condition.field),
         "comparator" => to_string(condition.comparator),
         "value" => condition.value,
         "value_to" => condition.value_to
       }}
    end)
  end

  defp force_params(params) do
    Map.update(params, "account_name", nil, &split_account_name/1)
  end

  defp split_account_name(""), do: nil
  defp split_account_name(value) when is_binary(value), do: String.split(value, ".")
  defp split_account_name(value), do: value

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
