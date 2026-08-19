# Implementation Plan: Excel Support in Importer Test / Preview Panel

## Goal
Enable testing Lua importers in `/automation/importers/new` and `/automation/importers/:id/edit` with Excel files (`.xlsx` and `.xls`) in addition to `.csv` files and CSV text.

## Tasks

- [x] **Task 1: Add Unit & LiveView Tests for Excel File Uploads in `ImporterLiveTest`**
  - In `apps/conta_web/test/conta_web/live/importer_live_test.exs`:
    - Add test for uploading `.xlsx` file using `file_input/4` and verifying script output.
    - Add test for uploading `.xls` (HTML/XML/OLE2) file and verifying script output.
    - Run tests to confirm failures before implementing upload changes.

- [x] **Task 2: Update `ContaWeb.ImporterLive.Form` to Support Multi-Format Uploads**
  - In `apps/conta_web/lib/conta_web/live/importer_live/form.ex`:
    - Alias `Conta.Reconciliation.ExcelImport`.
    - Add `allow_upload(:statement, accept: ~w(.csv .xlsx .xls), max_entries: 1)` in `mount/3`.
    - Add `handle_event("validate_test", _params, socket)` and `handle_event("cancel_upload", %{"ref" => ref}, socket)`.
    - In `handle_event("test_run", params, socket)`, check `consume_uploaded_entries/3` first, dispatching to `parse_statement(filename, content)` (which routes `.xlsx`/`.xls` to `ExcelImport.parse/1` and `.csv` to `CsvImport.parse/1`).
    - Fallback to textarea `parse_movements_csv(csv_text)` when no file is uploaded.

- [x] **Task 3: Update `form.html.heex` Template**
  - In `apps/conta_web/lib/conta_web/live/importer_live/form.html.heex`:
    - Update `<form phx-submit="test_run">` to `<form id="test-run-form" phx-change="validate_test" phx-submit="test_run">`.
    - Replace `CsvFileInput` with `<.live_file_input upload={@uploads.statement} ...>`.
    - Render uploaded file entry badges with cancel button.
    - Update labels and helper text.

- [x] **Task 4: Run Verification & Quality Checks**
  - Run `mix test apps/conta_web/test/conta_web/live/importer_live_test.exs`.
  - Run `mix compile --warnings-as-errors`, `mix format`, and full `mix test`.
