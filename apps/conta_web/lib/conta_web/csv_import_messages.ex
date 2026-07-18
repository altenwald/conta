defmodule ContaWeb.CsvImportMessages do
  @moduledoc """
  User-facing messages for `Conta.Reconciliation.CsvImport.parse/1` error
  results, shared by every conta_web view that accepts CSV input
  (ReconciliationLive.Upload's real bank-statement upload, ImporterLive.Form's
  CSV test-data panel).
  """
  use Gettext, backend: ContaWeb.Gettext

  @doc false
  # Public (rather than private) so it can be unit-tested directly: the
  # `:empty_file` case corresponds to a zero-byte upload, which
  # Phoenix.LiveViewTest's chunked-upload simulator (as of phoenix_live_view
  # 1.1.27) cannot itself reproduce — its UploadClient.progress_stats/2
  # divides by the entry's byte size, which raises ArithmeticError for a
  # genuinely empty file.
  def error_message([]), do: gettext("Please choose a file to upload")
  def error_message({:error, :empty_file}), do: gettext("The CSV data is empty")

  def error_message({:error, {:column_mismatch, line}}) do
    gettext("Row %{line} has a different number of columns than the header", line: line)
  end

  def error_message({:error, reason}), do: inspect(reason)
end
