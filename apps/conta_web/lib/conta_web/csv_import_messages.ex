defmodule ContaWeb.CsvImportMessages do
  @moduledoc """
  User-facing messages for `Conta.Reconciliation.CsvImport.parse/1` error
  results, shared by every conta_web view that accepts CSV input
  (ReconciliationLive.Upload's real bank-statement upload, ImporterLive.Form's
  CSV test-data panel).
  """
  use Gettext, backend: ContaWeb.Gettext

  @doc """
  Maps a CSV-import outcome to a user-facing message.

  Accepts:

    * `[]` — no upload entry was selected; returns a choose-a-file prompt.
    * `{:error, :empty_file}` — the CSV input had no content. Worded as "The
      CSV data is empty" rather than "The uploaded file is empty" because
      this covers both a zero-byte file upload (ReconciliationLive.Upload)
      and, in a later caller, a blank pasted-CSV textarea (ImporterLive.Form's
      test-data panel) — the wording avoids implying a file was necessarily
      involved.
    * `{:error, {:column_mismatch, line}}` — a data row had a different
      number of columns than the header; returns a message naming the line.
    * `{:error, reason}` — any other parse error; returns `inspect(reason)`.

  The `:empty_file` clause has a direct unit test (rather than relying only
  on integration coverage) because `Phoenix.LiveViewTest`'s chunked-upload
  simulator (as of phoenix_live_view 1.1.27) cannot itself reproduce a
  genuinely empty file — its `UploadClient.progress_stats/2` divides by the
  entry's byte size, which raises `ArithmeticError` when that size is 0.
  """
  def error_message([]), do: gettext("Please choose a file to upload")
  def error_message({:error, :empty_file}), do: gettext("The CSV data is empty")

  def error_message({:error, {:column_mismatch, line}}) do
    gettext("Row %{line} has a different number of columns than the header", line: line)
  end

  def error_message({:error, reason}), do: inspect(reason)
end
