defmodule ContaWeb.ReconciliationLive.Upload do
  use ContaWeb, :live_view

  alias Conta.Automator
  alias Conta.Ledger
  alias Conta.Reconciliation.CsvImport
  alias ContaWeb.CsvImportMessages

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Upload bank statement"))
     |> assign(:importers, Automator.list_importers())
     |> assign(:asset_accounts, Ledger.list_accounts(:assets))
     |> assign(:error, nil)
     |> assign(:imported_count, nil)
     |> allow_upload(:statement, accept: ~w(.csv), max_entries: 1)}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("remove", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :statement, ref)}
  end

  # sobelow_skip ["Traversal.FileModule"]
  def handle_event(
        "save",
        %{"importer_name" => importer_name, "asset_account_name" => asset_account_name},
        socket
      ) do
    with [csv] <-
           consume_uploaded_entries(socket, :statement, fn %{path: path}, _entry ->
             {:ok, File.read!(path)}
           end),
         {:ok, rows} <- CsvImport.parse(csv),
         account_name = String.split(asset_account_name, "."),
         :ok <- Automator.run_importer(importer_name, %{"movements" => rows}, account_name) do
      {:noreply,
       socket
       |> assign(:error, nil)
       |> assign(:imported_count, length(rows))
       |> put_flash(:info, gettext("Bank statement imported successfully"))}
    else
      reason -> {:noreply, assign(socket, :error, CsvImportMessages.error_message(reason))}
    end
  end
end
