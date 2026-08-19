# Importer CSV Test Data Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the Importer editor's "Test data" panel accept CSV (typed or loaded from a file) for its `movements` param, instead of hand-written JSON, matching the CSV shape the real production import path already uses.

**Architecture:** Extract the CSV-error-message formatting shared by `ReconciliationLive.Upload` and the importer test panel into a new `ContaWeb.CsvImportMessages` module (in `apps/conta_web`, not `apps/conta`, to respect the umbrella's one-way dependency — `conta` does not depend on `conta_web`). Switch `ImporterLive.Form`'s `movements` test control from a generic JSON textarea to a CSV textarea, parsed via the existing `Conta.Reconciliation.CsvImport.parse/1`. Add a small client-side JS hook that reads a chosen `.csv` file into that textarea. Add a matching format-help line to both CSV entry points.

**Tech Stack:** Elixir/Phoenix LiveView, ExUnit, `Phoenix.LiveViewTest`, vanilla JS (Phoenix hooks), esbuild.

**Spec:** `docs/superpowers/specs/2026-07-18-importer-csv-test-data-design.md`

---

### Task 1: `ContaWeb.CsvImportMessages` — extract the shared error-message formatter

**Files:**
- Create: `apps/conta_web/lib/conta_web/csv_import_messages.ex`
- Create: `apps/conta_web/test/conta_web/csv_import_messages_test.exs`
- Modify: `apps/conta_web/test/conta_web/live/reconciliation_live/upload_test.exs:124-131` (move these two tests out, update wording)

**Context:** `ReconciliationLive.Upload.error_message/1` (`apps/conta_web/lib/conta_web/live/reconciliation_live/upload.ex:52-67`) currently formats `Conta.Reconciliation.CsvImport.parse/1`'s error results into user-facing strings. It needs a new home shared by both `ReconciliationLive.Upload` and the importer test panel (Task 3) — it can't move into `Conta.Reconciliation.CsvImport` itself (that module lives in `apps/conta`, which has no dependency on `apps/conta_web`'s `Gettext` backend; check `apps/conta/mix.exs` — no `{:conta_web, in_umbrella: true}` entry).

The `:empty_file` message text changes from `"The uploaded file is empty"` to `"The CSV data is empty"`, because the same function will also cover a blank textarea (Task 3), not just a zero-byte upload.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule ContaWeb.CsvImportMessagesTest do
  use ExUnit.Case, async: true

  alias ContaWeb.CsvImportMessages

  test "maps an empty upload entry list to a choose-a-file message" do
    assert CsvImportMessages.error_message([]) == "Please choose a file to upload"
  end

  test "maps the empty-file parse error to a message" do
    assert CsvImportMessages.error_message({:error, :empty_file}) == "The CSV data is empty"
  end

  test "maps a column-mismatch parse error to a message with the line number" do
    assert CsvImportMessages.error_message({:error, {:column_mismatch, 3}}) ==
             "Row 3 has a different number of columns than the header"
  end

  test "maps any other error reason to its inspected value" do
    assert CsvImportMessages.error_message({:error, :boom}) == inspect(:boom)
  end
end
```

Save this to `apps/conta_web/test/conta_web/csv_import_messages_test.exs`.

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test apps/conta_web/test/conta_web/csv_import_messages_test.exs`
Expected: FAIL — `ContaWeb.CsvImportMessages` module not available / undefined function.

- [ ] **Step 3: Write the implementation**

```elixir
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
```

Save this to `apps/conta_web/lib/conta_web/csv_import_messages.ex`.

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test apps/conta_web/test/conta_web/csv_import_messages_test.exs`
Expected: PASS (4 tests, 0 failures)

- [ ] **Step 5: Move the equivalent tests out of `upload_test.exs`**

In `apps/conta_web/test/conta_web/live/reconciliation_live/upload_test.exs`, delete these two tests (lines 115-131 including the comment block above them — they're now redundant with Step 1's test file, and the assertion text is stale):

```elixir
  # A truly empty (0-byte) upload can't be driven through `render_upload/2`:
  # ...
  test "maps the empty-file error to the expected message" do
    assert ContaWeb.ReconciliationLive.Upload.error_message({:error, :empty_file}) ==
             "The uploaded file is empty"
  end

  test "maps unrecognized errors to their inspected reason" do
    assert ContaWeb.ReconciliationLive.Upload.error_message({:error, :boom}) == inspect(:boom)
  end
```

Don't run the suite yet — `ReconciliationLive.Upload.error_message/1` still exists at this point (Task 2 removes it), so leaving these in would still pass, but they're being superseded rather than kept as duplicates.

- [ ] **Step 6: Commit**

```bash
git add apps/conta_web/lib/conta_web/csv_import_messages.ex apps/conta_web/test/conta_web/csv_import_messages_test.exs apps/conta_web/test/conta_web/live/reconciliation_live/upload_test.exs
git commit -m "Add ContaWeb.CsvImportMessages, shared CSV error formatting"
```

---

### Task 2: `ReconciliationLive.Upload` — use the shared formatter, add format help text

**Files:**
- Modify: `apps/conta_web/lib/conta_web/live/reconciliation_live/upload.ex:1-68`
- Modify: `apps/conta_web/lib/conta_web/live/reconciliation_live/upload.html.heex:9-17`
- Test: `apps/conta_web/test/conta_web/live/reconciliation_live/upload_test.exs`

**Context:** `Conta.Reconciliation.CsvImport` (`apps/conta/lib/conta/reconciliation/csv_import.ex`) hardcodes `NimbleCSV.define(Parser, separator: ",", escape: "\"")` — comma-separated, `"`-escaped. Neither CSV entry point explains this today; a semicolon-separated file (common in Spanish/European exports) just fails with an unexplained column-mismatch error. This task adds a one-line hint near the file input, and switches the view's error formatting to the module from Task 1.

- [ ] **Step 1: Write the failing test for the help text**

Add to `apps/conta_web/test/conta_web/live/reconciliation_live/upload_test.exs`, inside the existing `setup` block's test group (any test that does a plain `live/2` mount works — add a new one):

```elixir
  test "shows the expected CSV format", %{conn: conn, user: user} do
    conn = log_in_user(conn, user)
    {:ok, _view, html} = live(conn, ~p"/ledger/reconciliation/upload")

    assert html =~ "Comma-separated CSV"
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test apps/conta_web/test/conta_web/live/reconciliation_live/upload_test.exs`
Expected: FAIL on the new test — "Comma-separated CSV" not found in the rendered HTML. (Other tests should still pass at this point.)

- [ ] **Step 3: Update `upload.ex`**

Replace the `alias` block and delete the local `error_message/1` (lines 1-67 currently). Resulting top and bottom of the module:

```elixir
defmodule ContaWeb.ReconciliationLive.Upload do
  use ContaWeb, :live_view

  alias Conta.Automator
  alias Conta.Ledger
  alias Conta.Reconciliation.CsvImport
  alias ContaWeb.CsvImportMessages

  # ... mount/3, handle_event/3 unchanged ...

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
```

The `error_message/1` function and its `@doc false` comment block are deleted entirely — `handle_event("save", ...)`'s `else` clause is the only caller, and it now calls `CsvImportMessages.error_message/1`.

- [ ] **Step 4: Add the format help text to `upload.html.heex`**

In `apps/conta_web/lib/conta_web/live/reconciliation_live/upload.html.heex`, right after the file `<.input>` (currently lines 9-16):

```heex
      <.input
        type="file"
        name="statement"
        upload={@uploads.statement}
        files={[]}
        phx-target={nil}
        label={gettext("Bank statement (CSV)")}
      />
      <p class="text-sm opacity-70 mt-1">
        {gettext("Comma-separated CSV, double quotes (\") to escape values containing commas or newlines.")}
      </p>
```

- [ ] **Step 5: Run the full upload test file**

Run: `mix test apps/conta_web/test/conta_web/live/reconciliation_live/upload_test.exs`
Expected: PASS, all tests (the new format-help test, plus the pre-existing upload/error tests using the now-shared `CsvImportMessages`).

- [ ] **Step 6: Commit**

```bash
git add apps/conta_web/lib/conta_web/live/reconciliation_live/upload.ex apps/conta_web/lib/conta_web/live/reconciliation_live/upload.html.heex apps/conta_web/test/conta_web/live/reconciliation_live/upload_test.exs
git commit -m "Reuse ContaWeb.CsvImportMessages in ReconciliationLive.Upload, add CSV format hint"
```

---

### Task 3: `ImporterLive.Form` — switch the `movements` test panel from JSON to CSV

**Files:**
- Modify: `apps/conta_web/lib/conta_web/live/importer_live/form.ex`
- Modify: `apps/conta_web/lib/conta_web/live/importer_live/form.html.heex:29-45`
- Test: `apps/conta_web/test/conta_web/live/importer_live_test.exs:103-129`

**Context:** Today, the `movements` param is rendered by the shared `<.test_param_input>`/`render_control(:table)` (`apps/conta_web/lib/conta_web/components/automator_components.ex:133-142`), and `handle_event("test_run", ...)` (`form.ex:76-85`) passes the textarea's raw text straight to `Automator.test_run_importer/2`, which JSON-decodes it. This task replaces that with a CSV-specific control and parses with `Conta.Reconciliation.CsvImport.parse/1` instead — `Automator.test_run_importer/2` itself needs no change, since its `cast/3` helper already handles a pre-decoded list of maps (`apps/conta/lib/conta/automator.ex:486-487`, the `other -> to_list(other)` clause), which is exactly what `CsvImport.parse/1` returns.

A blank textarea must keep testing against an empty table (`[]`), not raise `:empty_file` — that's the current behavior with blank JSON and this task preserves it by special-casing blank input before calling `CsvImport.parse/1`.

- [ ] **Step 1: Write the failing tests**

Replace the existing test at `apps/conta_web/test/conta_web/live/importer_live_test.exs:103-129` (`"test-runs the fixed movements table param's raw JSON test data through the script"`) with:

```elixir
    test "test-runs the fixed movements table param's CSV test data through the script", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/importers/new")

      code = ~S"""
      local total = 0
      for _, row in ipairs(movements) do
        total = total + tonumber(row.amount)
      end
      return {status = "ok", commands = {{type = "total", data = {total = total}}}}
      """

      form_live
      |> form("#importer-form", set_importer: %{name: "sum rows", code: code})
      |> render_change()

      csv = "amount\n10\n5\n"

      html =
        form_live
        |> element("form[phx-submit=test_run]")
        |> render_submit(%{"test_params" => %{"movements" => csv}})

      assert html =~ "total"
      assert html =~ "15"
    end

    test "shows a column-mismatch error for malformed CSV test data", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/importers/new")

      code = ~S[return {status = "ok", commands = {}}]

      form_live
      |> form("#importer-form", set_importer: %{name: "malformed csv", code: code})
      |> render_change()

      csv = "date,amount\n2026-07-01\n"

      html =
        form_live
        |> element("form[phx-submit=test_run]")
        |> render_submit(%{"test_params" => %{"movements" => csv}})

      assert html =~ "Row 2 has a different number of columns than the header"
    end

    test "treats blank movements test data as an empty table, not an error", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/importers/new")

      code = ~S"""
      local count = 0
      for _ in ipairs(movements) do count = count + 1 end
      return {status = "ok", commands = {{type = "count", data = {count = count}}}}
      """

      form_live
      |> form("#importer-form", set_importer: %{name: "count rows", code: code})
      |> render_change()

      html =
        form_live
        |> element("form[phx-submit=test_run]")
        |> render_submit(%{"test_params" => %{"movements" => ""}})

      refute html =~ "Error"
      assert html =~ "count"
    end
```

Keep the other two existing "Form" tests (`"creates a new importer"`, `"edits an existing importer"`, and `"test-runs the Lua code and shows the commands without dispatching them"`) as-is.

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test apps/conta_web/test/conta_web/live/importer_live_test.exs`
Expected: FAIL on the three new/replaced tests — the CSV text currently gets `Jason.decode`d as JSON and fails, so `movements` ends up empty/invalid rather than the expected rows; the column-mismatch test won't show that specific message (nothing parses CSV yet); the blank-input test may already incidentally pass (blank already means `[]` today) — that's fine, it should still be included for regression coverage going forward.

- [ ] **Step 3: Update `form.ex`**

```elixir
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
    {:ok, assign(socket, :test_result, nil)}
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
        {:error, reason} -> {:error, CsvImportMessages.error_message(reason)}
      end

    {:noreply, assign(socket, :test_result, format_test_result(result))}
  end

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
```

Note what's removed versus the current file: the `@movements_param` module attribute, the `alias Conta.Projector.Automator.Param` it existed solely for, and the `:movements_param` assign in `mount/3` are all gone — nothing else in the module referenced `Param`.

- [ ] **Step 4: Update `form.html.heex`**

Replace (current lines 29-45, the whole "Test data" card):

```heex
  <div class="card bg-base-100 shadow-xl border border-base-200 p-4 mt-6">
    <h2 class="font-semibold mb-2">{gettext("Test data")}</h2>
    <p class="text-sm opacity-70 mb-2">
      {gettext("Running here never dispatches real commands — it only shows what would be generated.")}
    </p>
    <form phx-submit="test_run">
      <.test_param_input param={@movements_param} />
      <div class="flex flex-wrap items-center gap-2 mt-2">
        <button type="submit" class="btn btn-primary">{gettext("Run")}</button>
      </div>
    </form>

    <div :if={@test_result} class="mt-4">
      <p :if={elem(@test_result, 0) == :error} class="text-error font-semibold">{gettext("Error")}</p>
      <pre class="bg-base-200 p-4 rounded overflow-x-auto text-sm">{elem(@test_result, 1)}</pre>
    </div>
  </div>
```

with:

```heex
  <div class="card bg-base-100 shadow-xl border border-base-200 p-4 mt-6">
    <h2 class="font-semibold mb-2">{gettext("Test data")}</h2>
    <p class="text-sm opacity-70 mb-2">
      {gettext("Running here never dispatches real commands — it only shows what would be generated.")}
    </p>
    <form phx-submit="test_run">
      <div class="fieldset mb-2">
        <label for="test_params_movements">
          <span class="label mb-1">{gettext("movements (CSV)")}</span>
        </label>
        <input
          type="file"
          accept=".csv"
          id="movements-csv-file"
          phx-hook="CsvFileInput"
          data-target="test_params_movements"
          class="file-input file-input-bordered w-full mb-2"
        />
        <textarea
          id="test_params_movements"
          name="test_params[movements]"
          class="w-full textarea textarea-bordered font-mono text-sm"
          rows="6"
        ></textarea>
        <p class="text-sm opacity-70 mt-1">
          {gettext("Comma-separated CSV, double quotes (\") to escape values containing commas or newlines.")}
        </p>
      </div>
      <div class="flex flex-wrap items-center gap-2 mt-2">
        <button type="submit" class="btn btn-primary">{gettext("Run")}</button>
      </div>
    </form>

    <div :if={@test_result} class="mt-4">
      <p :if={elem(@test_result, 0) == :error} class="text-error font-semibold">{gettext("Error")}</p>
      <pre class="bg-base-200 p-4 rounded overflow-x-auto text-sm">{elem(@test_result, 1)}</pre>
    </div>
  </div>
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test apps/conta_web/test/conta_web/live/importer_live_test.exs`
Expected: PASS, all tests including the three new/replaced ones.

- [ ] **Step 6: Commit**

```bash
git add apps/conta_web/lib/conta_web/live/importer_live/form.ex apps/conta_web/lib/conta_web/live/importer_live/form.html.heex apps/conta_web/test/conta_web/live/importer_live_test.exs
git commit -m "Switch Importer test-data panel from JSON to CSV movements input"
```

---

### Task 4: `CsvFileInput` JS hook — load a `.csv` file into the textarea client-side

**Files:**
- Create: `apps/conta_web/assets/js/hooks/csv_file_input.js`
- Modify: `apps/conta_web/assets/js/hooks/index.js`

**Context:** The file input added in Task 3 (`id="movements-csv-file"`, `phx-hook="CsvFileInput"`, `data-target="test_params_movements"`) needs a hook that reads the chosen file and writes its text into the textarea — purely client-side, no `allow_upload`/server round-trip, following the same hook pattern already used by `MonacoEditor` (`apps/conta_web/assets/js/hooks/monaco_editor.js`). There's no JS test harness in this project (no `*.test.js`/`*.spec.js` outside `node_modules`), so this task's only verification is that the asset bundle builds cleanly and a manual browser check.

- [ ] **Step 1: Create the hook**

```js
const CsvFileInput = {
  mounted() {
    this.el.addEventListener("change", (event) => {
      const file = event.target.files[0];
      if (!file) return;

      const target = document.getElementById(this.el.dataset.target);
      if (!target) {
        console.error("CsvFileInput hook: could not find target textarea", this.el.dataset.target);
        return;
      }

      const reader = new FileReader();
      reader.onload = () => {
        target.value = reader.result;
      };
      reader.readAsText(file);
    });
  },
};

export default CsvFileInput;
```

Save to `apps/conta_web/assets/js/hooks/csv_file_input.js`.

- [ ] **Step 2: Register the hook**

Update `apps/conta_web/assets/js/hooks/index.js`:

```js
import MonacoEditor from "./monaco_editor";
import CsvFileInput from "./csv_file_input";

export default {
  MonacoEditor,
  CsvFileInput,
};
```

- [ ] **Step 3: Build the assets to confirm no syntax/bundling errors**

Run (from the repo root): `cd apps/conta_web && mix assets.build`
Expected: exits 0, no esbuild errors referencing `csv_file_input.js` or `hooks/index.js`.

- [ ] **Step 4: Manual verification in the browser**

<user needs to run this — requires a running `mix phx.server`; per this project's standing convention, ask before starting/stopping it if one might already be running>

1. Navigate to `/automation/importers/new`.
2. In the "Test data" panel, click the new file input and choose a small `.csv` file (e.g. `date,description,amount\n2026-07-01,TEST,-10\n`).
3. Confirm the textarea below it fills with that file's raw text.
4. Confirm the textarea remains editable afterward and "Run" still works against the loaded content.

- [ ] **Step 5: Commit**

```bash
git add apps/conta_web/assets/js/hooks/csv_file_input.js apps/conta_web/assets/js/hooks/index.js
git commit -m "Add CsvFileInput hook to load a CSV file into a textarea"
```

---

### Task 5: Extract gettext strings

**Files:**
- Modify: gettext `.pot`/`.po` files under `apps/conta_web/priv/gettext/` (exact set depends on configured locales — check `apps/conta_web/priv/gettext/` for existing locale directories)

**Context:** Two new translatable strings were introduced: `"movements (CSV)"` (form.html.heex) and `"Comma-separated CSV, double quotes (\") to escape values containing commas or newlines."` (used in both `upload.html.heex` and `form.html.heex`, plus its `ContaWeb.CsvImportMessages`-formatted counterparts from Task 1). They need to be extracted and merged into the locale files so translators can pick them up.

- [ ] **Step 1: Extract and merge**

Run: `cd apps/conta_web && mix gettext.extract --merge`
Expected: exits 0; `git status` shows changes under `apps/conta_web/priv/gettext/` (new msgids added, none removed unexpectedly — double check nothing besides the new strings and the `:empty_file` wording change from Task 1 shows up as removed/changed).

- [ ] **Step 2: Commit**

```bash
git add apps/conta_web/priv/gettext/
git commit -m "Extract gettext strings for the Importer CSV test-data panel"
```

---

### Task 6: Full-suite verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `mix test`
Expected: PASS, 0 failures, no regressions in `apps/conta` or `apps/conta_web`.

- [ ] **Step 2: Compile with warnings-as-errors to catch the removed alias/attribute cleanly**

Run: `mix compile --warnings-as-errors --force`
Expected: exits 0 — in particular, confirms `ImporterLive.Form` has no leftover unused `Param`/`@movements_param` reference (Task 3, Step 3) and `ReconciliationLive.Upload` has no leftover unused `error_message/1` reference.

No commit for this task — it's a verification checkpoint. If either step fails, fix the underlying task before proceeding to @superpowers:requesting-code-review.
