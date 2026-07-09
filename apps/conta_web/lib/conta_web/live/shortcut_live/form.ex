defmodule ContaWeb.ShortcutLive.Form do
  use ContaWeb, :live_view

  import Ecto.Changeset, only: [get_field: 2]
  import Conta.Commanded.Application, only: [dispatch: 1]
  import ContaWeb.AutomatorComponents

  require Logger

  alias Conta.Automator
  alias Conta.Automator.TableSources
  alias Conta.Command.SetShortcut

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :test_result, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    set_shortcut = Automator.new_set_shortcut()

    socket
    |> assign(:page_title, gettext("New Shortcut"))
    |> assign(:set_shortcut, set_shortcut)
    |> assign(:form_params, %{})
    |> assign_form(SetShortcut.changeset(set_shortcut, %{}))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    set_shortcut = Automator.get_set_shortcut(id)

    socket
    |> assign(:page_title, gettext("Edit Shortcut"))
    |> assign(:set_shortcut, set_shortcut)
    |> assign(:form_params, %{})
    |> assign_form(SetShortcut.changeset(set_shortcut, %{}))
  end

  @impl true
  def handle_event("validate", %{"set_shortcut" => params}, socket) do
    changeset =
      socket.assigns.set_shortcut
      |> SetShortcut.changeset(force_constants(params))
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:form_params, params) |> assign_form(changeset)}
  end

  def handle_event("add_param", _params, socket) do
    params =
      Map.update(socket.assigns.form_params, "params", %{"0" => %{}}, fn existing ->
        Map.put(existing, to_string(map_size(existing)), %{})
      end)

    changeset =
      socket.assigns.set_shortcut
      |> SetShortcut.changeset(force_constants(params))
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:form_params, params) |> assign_form(changeset)}
  end

  def handle_event("del_param", %{"index" => index}, socket) do
    params = Map.update(socket.assigns.form_params, "params", %{}, &Map.delete(&1, index))

    changeset =
      socket.assigns.set_shortcut
      |> SetShortcut.changeset(force_constants(params))
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:form_params, params) |> assign_form(changeset)}
  end

  def handle_event("save", %{"set_shortcut" => params}, socket) do
    changeset = SetShortcut.changeset(socket.assigns.set_shortcut, force_constants(params))

    if changeset.valid? and dispatch(SetShortcut.to_command(changeset)) == :ok do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Shortcut saved successfully"))
       |> push_navigate(to: ~p"/automation/shortcuts")}
    else
      Logger.debug("changeset errors: #{inspect(changeset.errors)}")

      {:noreply,
       socket
       |> assign(:form_params, params)
       |> assign_form(Map.put(changeset, :action, :validate))}
    end
  end

  def handle_event("test_run", params, socket) do
    raw_test_params = Map.get(params, "test_params", %{})
    changeset = socket.assigns.form.source
    code = get_field(changeset, :code) || ""
    params_defs = get_field(changeset, :params) || []
    test_params = cast_test_params(params_defs, raw_test_params)

    result = Automator.test_run_shortcut(params_defs, code, test_params)

    {:noreply, assign(socket, :test_result, format_test_result(result))}
  end

  def handle_event("load_table_sample", %{"param" => name}, socket) do
    param = Enum.find(socket.assigns.params_defs, &(&1.name == name))
    limit = (param && param.sample_limit) || TableSources.default_sample_limit()

    case TableSources.sample(name, limit) do
      {:error, :unknown_source} ->
        {:noreply, put_flash(socket, :error, gettext("Unknown data source"))}

      sample ->
        json = Jason.encode!(sample, pretty: true)

        form_params =
          Map.update(socket.assigns.form_params, "test_params", %{name => json}, &Map.put(&1, name, json))

        {:noreply, assign(socket, :form_params, form_params)}
    end
  end

  defp force_constants(params) do
    params
    |> Map.put("automator", "automator")
    |> Map.put("language", "lua")
    |> Map.update("params", %{}, &normalize_param_options/1)
  end

  defp normalize_param_options(params) do
    Map.new(params, fn {idx, param} ->
      param =
        case param["options"] do
          options when is_binary(options) ->
            Map.put(
              param,
              "options",
              options |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
            )

          _ ->
            param
        end

      {idx, param}
    end)
  end

  defp cast_test_params(params_defs, raw_test_params) do
    Map.new(params_defs, fn param ->
      raw_value = raw_test_params[param.name]

      value =
        case param.type do
          :table ->
            case Jason.decode(raw_value || "") do
              {:ok, decoded} -> decoded
              {:error, _} -> raw_value
            end

          _ ->
            raw_value
        end

      {param.name, value}
    end)
  end

  defp format_test_result({:ok, result}), do: {:ok, Jason.encode!(result, pretty: true)}
  defp format_test_result({:error, reason}), do: {:error, inspect(reason)}

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    socket
    |> assign(:form, to_form(changeset))
    |> assign(:params_defs, get_field(changeset, :params) || [])
  end
end
