# Design: Excel Support in Importer Test / Preview Panel

## Context
When creating or editing importers in `/automation/importers/new` or `/automation/importers/:id/edit`, users can test their Lua scripts in the "Test data" panel without creating real ledger transactions. Previously, this test panel only accepted `.csv` files via client-side text extraction or direct CSV pasting in the textarea.

Since bank statements frequently come in Excel formats (`.xlsx` and `.xls`), the test runner must support uploading `.xlsx` and `.xls` files directly alongside CSVs.

## Architecture & Design

1. **LiveView Upload Configuration (`ContaWeb.ImporterLive.Form`)**:
   - Add `allow_upload(:statement, accept: ~w(.csv .xlsx .xls), max_entries: 1)` in `mount/3`.
   - Add `handle_event("validate_test", _params, socket)` to handle live file upload state changes.
   - Add `handle_event("cancel_upload", %{"ref" => ref}, socket)` to cancel attached file uploads.

2. **Execution Flow in `handle_event("test_run", params, socket)`**:
   - Consume uploaded entries from `:statement`:
     - If a file is uploaded, determine format by extension (`.xlsx`, `.xls` vs `.csv`) and parse with `Conta.Reconciliation.ExcelImport.parse/1` or `Conta.Reconciliation.CsvImport.parse/1`.
     - If no file is uploaded, fallback to reading the CSV textarea via `parse_movements_csv/1`.
   - Run `Automator.test_run_importer(code, rows)` with parsed rows.
   - Render results or errors in the `@test_result` container.

3. **User Interface (`form.html.heex`)**:
   - Update label from `"movements (CSV)"` to `"Movements (CSV or Excel)"`.
   - Use `<.live_file_input upload={@uploads.statement} class="file-input file-input-bordered w-full mb-2" />` for file selection.
   - Show uploaded file entries with remove buttons.
   - Retain the textarea for quick manual CSV text pasting when no file is uploaded.
   - Update helper text to mention `.csv`, `.xlsx`, and `.xls`.

4. **Testing**:
   - Test CSV test run via textarea (existing).
   - Test CSV test run via uploaded file.
   - Test Excel (`.xlsx` and `.xls`) test run via uploaded file using `file_input/4`.
