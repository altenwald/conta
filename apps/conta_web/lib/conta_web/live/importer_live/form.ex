defmodule ContaWeb.ImporterLive.Form do
  use ContaWeb, :live_view

  import Ecto.Changeset, only: [get_field: 2]
  import Conta.Commanded.Application, only: [dispatch: 1]
  import ContaWeb.AutomatorComponents

  require Logger

  alias Conta.Automator
  alias Conta.Command.SetImporter
  alias Conta.Reconciliation.CsvImport
  alias ContaWeb.CsvImportMessages

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:test_result, nil)
     |> assign(:test_movements, "")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    set_importer = Automator.new_set_importer()

    socket
    |> assign(:page_title, gettext("New Importer"))
    |> assign(:set_importer, set_importer)
    |> assign_form(SetImporter.changeset(set_importer, %{}))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    set_importer = Automator.get_set_importer(id)
    changeset = SetImporter.changeset(set_importer, %{})

    socket
    |> assign(:page_title, gettext("Edit Importer"))
    |> assign(:set_importer, set_importer)
    |> assign_form(changeset)
  end

  @impl true
  def handle_event("validate", %{"set_importer" => params}, socket) do
    changeset =
      socket.assigns.set_importer
      |> SetImporter.changeset(force_constants(params))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"set_importer" => params}, socket) do
    changeset = SetImporter.changeset(socket.assigns.set_importer, force_constants(params))

    if changeset.valid? and dispatch(SetImporter.to_command(changeset)) == :ok do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Importer saved successfully"))
       |> push_navigate(to: ~p"/automation/importers")}
    else
      Logger.debug("changeset errors: #{inspect(changeset.errors)}")

      {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
    end
  end

  def handle_event("test_run", params, socket) do
    raw_test_params = Map.get(params, "test_params", %{})
    changeset = socket.assigns.form.source
    code = get_field(changeset, :code) || ""
    csv_text = raw_test_params["movements"] || ""

    result =
      case parse_movements_csv(csv_text) do
        {:ok, rows} -> Automator.test_run_importer(code, rows)
        error -> {:error, CsvImportMessages.error_message(error)}
      end

    {:noreply,
     socket
     |> assign(:test_result, format_test_result(result))
     |> assign(:test_movements, csv_text)}
  end

  # A blank test panel means "test against zero rows", not "no file was
  # provided" - unlike ReconciliationLive.Upload's real import flow, where an
  # empty file is a genuine error, leaving this textarea empty is a
  # legitimate way to check how the script behaves with no movements. So we
  # special-case it to an empty table here rather than letting it fall
  # through to CsvImport.parse/1's `{:error, :empty_file}`.
  defp parse_movements_csv(csv_text) do
    if String.trim(csv_text) == "" do
      {:ok, []}
    else
      CsvImport.parse(csv_text)
    end
  end

  defp force_constants(params) do
    params
    |> Map.put("automator", "automator")
    |> Map.put("language", "lua")
  end

  defp format_test_result({:ok, result}), do: {:ok, Jason.encode!(result, pretty: true)}
  defp format_test_result({:error, reason}) when is_binary(reason), do: {:error, reason}
  defp format_test_result({:error, reason}), do: {:error, inspect(reason)}

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
