defmodule ContaWeb.ReconciliationLive.Upload do
  use ContaWeb, :live_view

  alias Conta.Automator
  alias Conta.Ledger
  alias Conta.Reconciliation.CsvImport

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
      reason -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @doc false
  # Maps the possible failure results of the "save" event's `with/else` chain
  # to the message shown to the user. Public (rather than private) so it can
  # be unit-tested directly: the `:empty_file` case corresponds to a
  # zero-byte upload, which `Phoenix.LiveViewTest`'s chunked-upload simulator
  # (as of phoenix_live_view 1.1.27) cannot itself reproduce — its
  # `UploadClient.progress_stats/2` divides by the entry's byte size, which
  # raises `ArithmeticError` for a genuinely empty file.
  def error_message([]), do: gettext("Please choose a file to upload")
  def error_message({:error, :empty_file}), do: gettext("The uploaded file is empty")

  def error_message({:error, {:column_mismatch, line}}) do
    gettext("Row %{line} has a different number of columns than the header", line: line)
  end

  def error_message({:error, reason}), do: inspect(reason)
end
