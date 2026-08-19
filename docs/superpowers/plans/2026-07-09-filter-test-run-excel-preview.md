# Filter Test-Run Excel Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a filter's output format is Excel (`:xlsx`), the "Test data" panel in `ContaWeb.FilterLive.Form` (`/automation/filters/new` and `/automation/filters/:id/edit`) renders the test-run result as an HTML table (headers + rows) instead of raw JSON.

**Architecture:** Extract the sheet-shaping logic already embedded in `Conta.Automator.Excel.export/2` into a shared private `shape_sheets/1`, expose it via a new public `Excel.to_sheets/1` that returns `{:ok, sheets} | :error`. `FilterLive.Form` reads the filter's `output` field when handling `"test_run"` and tags the result as `{:table, sheets}`, `{:json, json}`, `{:json_fallback, json}`, or `{:error, message}`. The template renders each tag differently; only `:table` gets an HTML `<table>`.

**Tech Stack:** Elixir, Phoenix LiveView, HEEx, ExUnit, Phoenix.LiveViewTest.

**Spec:** `docs/superpowers/specs/2026-07-09-filter-test-run-excel-preview-design.md`

---

## Task 1: `Conta.Automator.Excel` — extract `shape_sheets/1` and add `to_sheets/1`

**Files:**
- Modify: `apps/conta/lib/conta/automator/excel.ex`
- Test: `apps/conta/test/conta/automator/excel_test.exs` (new file)

This task is self-contained: it changes no other module's behavior and can be verified in isolation.

- [ ] **Step 1: Write the failing tests**

Create `apps/conta/test/conta/automator/excel_test.exs`:

```elixir
defmodule Conta.Automator.ExcelTest do
  use ExUnit.Case, async: true

  alias Conta.Automator.Excel

  describe "to_sheets/1" do
    test "returns {:ok, []} for an empty list" do
      assert {:ok, []} = Excel.to_sheets([])
    end

    test "returns {:ok, []} for an empty map" do
      assert {:ok, []} = Excel.to_sheets(%{})
    end

    test "passes through an explicit name/headers/rows shape untouched" do
      workbook = [%{"name" => "Sheet1", "headers" => ["a", "b"], "rows" => [[1, 2]]}]
      assert {:ok, ^workbook} = Excel.to_sheets(workbook)
    end

    test "derives headers and rows from a plain list of maps" do
      data = [%{"a" => 1, "b" => 2}, %{"a" => 3, "b" => 4}]

      assert {:ok, [%{"name" => "No name", "headers" => headers, "rows" => rows}]} =
               Excel.to_sheets(data)

      assert Enum.sort(headers) == ["a", "b"]
      assert length(rows) == 2
    end

    test "derives one sheet per key for a map of sheet_name => rows" do
      data = %{"expenses" => [%{"amount" => 100}], "invoices" => [%{"amount" => 200}]}

      assert {:ok, sheets} = Excel.to_sheets(data)
      assert length(sheets) == 2
      assert Enum.all?(sheets, &(&1["headers"] == ["amount"]))
    end

    test "returns :error for a scalar result" do
      assert :error = Excel.to_sheets(42)
      assert :error = Excel.to_sheets("just a string")
    end

    test "returns :error for a list that isn't map-shaped" do
      assert :error = Excel.to_sheets([1, 2, 3])
    end
  end

  describe "export/2 regression" do
    test "completes for an empty list instead of recursing forever" do
      task = Task.async(fn -> Excel.export([], "empty.xlsx") end)
      assert {:ok, {_filename, _content}} = Task.await(task, 2_000)
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test apps/conta/test/conta/automator/excel_test.exs`
Expected: compile error or `UndefinedFunctionError` — `Conta.Automator.Excel.to_sheets/1` doesn't exist yet. The regression test will hang instead of failing cleanly (this is the bug being fixed) — if it hangs past a few seconds, cancel it (Ctrl-C) rather than waiting out the full timeout; that hang is itself the confirmation the test is exercising real (broken) behavior.

- [ ] **Step 3: Refactor `excel.ex`**

Replace the full contents of `apps/conta/lib/conta/automator/excel.ex` with:

```elixir
defmodule Conta.Automator.Excel do
  alias Elixlsx.Sheet
  alias Elixlsx.Workbook

  @unnamed "No name"

  defp col(0), do: ""

  defp col(i) when is_integer(i) do
    base = ?Z - ?A + 1
    unit = rem(i - 1, base)
    col(div(i - 1, base)) <> <<unit + ?A>>
  end

  def export(data, filename) do
    data
    |> shape_sheets()
    |> build_workbook()
    |> Elixlsx.write_to_memory(filename)
  end

  @doc """
  Normalizes any of the shapes accepted by `export/2` into a plain list of
  `%{"name" => _, "headers" => _, "rows" => _}` sheets, without writing an
  actual workbook. Returns `:error` (instead of raising) for any other shape,
  since the input comes from an arbitrary Lua script's return value.
  """
  @spec to_sheets(term()) :: {:ok, [map()]} | :error
  def to_sheets(data) do
    {:ok, shape_sheets(data)}
  rescue
    _ -> :error
  end

  defp shape_sheets([]), do: []

  defp shape_sheets([%{"name" => _, "rows" => _, "headers" => _} | _] = workbook), do: workbook

  defp shape_sheets(sheet_data) when is_list(sheet_data), do: shape_sheets(%{@unnamed => sheet_data})

  defp shape_sheets(workbook) when is_map(workbook) do
    Enum.map(workbook, fn {sheet_name, [first_row | _] = sheet_data} ->
      headers = Map.keys(first_row)
      rows = Enum.map(sheet_data, &get_headers(headers, &1))
      %{"name" => sheet_name, "headers" => headers, "rows" => rows}
    end)
  end

  defp build_workbook(sheets) do
    set_cell = fn {content, idx}, sheet, jdx ->
      Sheet.set_cell(sheet, "#{col(idx)}#{jdx}", to_cell(content))
    end

    Enum.reduce(sheets, %Workbook{}, fn %{"name" => name, "rows" => rows, "headers" => headers}, workbook ->
      sheet =
        headers
        |> Enum.with_index(1)
        |> Enum.reduce(Sheet.with_name(name), &set_cell.(&1, &2, 1))

      sheet =
        rows
        |> Enum.with_index(2)
        |> Enum.reduce(sheet, fn {row, i}, sheet ->
          row
          |> to_list()
          |> Enum.with_index(1)
          |> Enum.reduce(sheet, &set_cell.(&1, &2, i))
        end)

      Workbook.append_sheet(workbook, sheet)
    end)
  end

  defp get_headers(headers, row) when is_struct(row), do: get_headers(headers, Map.from_struct(row))
  defp get_headers(headers, row), do: Enum.map(headers, &row[&1])

  defp to_cell(atom) when is_atom(atom), do: to_string(atom)
  defp to_cell(integer) when is_integer(integer), do: integer
  defp to_cell(float) when is_float(float), do: float
  defp to_cell(string) when is_binary(string), do: string
  defp to_cell(date) when is_struct(date, Date), do: to_string(date)
  defp to_cell(datetime) when is_struct(datetime, DateTime), do: to_string(datetime)
  defp to_cell(datetime) when is_struct(datetime, NaiveDateTime), do: to_string(datetime)
  defp to_cell(_otherwise), do: "(cannot convert)"

  defp to_list(struct) when is_struct(struct), do: to_list(Map.from_struct(struct))
  defp to_list(map) when is_map(map), do: Map.values(map)
  defp to_list(list) when is_list(list), do: list
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test apps/conta/test/conta/automator/excel_test.exs`
Expected: `7 tests, 0 failures` (all `to_sheets/1` cases plus the `export/2` regression test, which now returns instead of hanging).

- [ ] **Step 5: Run the full `conta` app test suite to check for regressions**

Run: `mix test apps/conta/test`
Expected: same pass count as before this change (no new failures) — this refactor must not change `export/2`'s behavior for real data.

- [ ] **Step 6: Commit**

```bash
git add apps/conta/lib/conta/automator/excel.ex apps/conta/test/conta/automator/excel_test.exs
git commit -m "Extract Excel sheet-shaping into to_sheets/1, fix export([]) infinite recursion"
```

---

## Task 2: `FilterLive.Form` — render a table for `output: :xlsx` test runs

**Files:**
- Modify: `apps/conta_web/lib/conta_web/live/filter_live/form.ex`
- Modify: `apps/conta_web/lib/conta_web/live/filter_live/form.html.heex`
- Test: `apps/conta_web/test/conta_web/live/filter_live_test.exs`

Depends on Task 1 (`Excel.to_sheets/1` must exist). Backend and template changes are done together because the existing `format_test_result/1` and the `<pre>{elem(@test_result, 1)}</pre>` block are tightly coupled — changing one without the other leaves the LiveView unable to render a `{:table, sheets}` tuple at all (HEEx has no `Phoenix.HTML.Safe` implementation for a bare list of maps, so it would raise, not just look wrong).

- [ ] **Step 1: Write the failing LiveView tests**

Add to the `describe "Form"` block in `apps/conta_web/test/conta_web/live/filter_live_test.exs` (after the existing `"test-runs the Lua code without dispatching anything"` test):

```elixir
    test "shows an HTML table when output is xlsx and the script returns row data", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/new")

      code = ~S"""
      return {{name = "Alice", amount = 100}, {name = "Bob", amount = 200}}
      """

      form_live
      |> form("#filter-form", set_filter: %{name: "table filter", code: code, output: "xlsx"})
      |> render_change()

      html = form_live |> element("form[phx-submit=test_run]") |> render_submit()

      assert html =~ "<table"
      assert html =~ "Alice"
      assert html =~ "Bob"
      assert html =~ "amount"
    end

    test "falls back to raw JSON when output is xlsx but the result has no table shape", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/new")

      form_live
      |> form("#filter-form", set_filter: %{name: "scalar filter", code: "return 42", output: "xlsx"})
      |> render_change()

      html = form_live |> element("form[phx-submit=test_run]") |> render_submit()

      refute html =~ "<table"
      assert html =~ "42"
      assert html =~ "table shape"
    end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test apps/conta_web/test/conta_web/live/filter_live_test.exs`
Expected: both new tests FAIL — today's code always renders JSON in a `<pre>`, ignoring `output`, so `html =~ "<table"` is false in the first test and `html =~ "table shape"` is false in the second.

- [ ] **Step 3: Update `form.ex`**

Add `Excel` to the aliases (near the top, alongside the existing `alias Conta.Automator` and `alias Conta.Command.SetFilter`):

```elixir
  alias Conta.Automator
  alias Conta.Automator.Excel
  alias Conta.Command.SetFilter
```

Replace the `"test_run"` handler:

```elixir
  def handle_event("test_run", params, socket) do
    raw_test_params = Map.get(params, "test_params", %{})
    changeset = socket.assigns.form.source
    code = get_field(changeset, :code) || ""
    params_defs = get_field(changeset, :params) || []
    output = get_field(changeset, :output)
    test_params = cast_test_params(params_defs, raw_test_params)

    result = Automator.test_run_filter(params_defs, code, test_params)

    {:noreply, assign(socket, :test_result, build_test_result(output, result))}
  end
```

Replace `format_test_result/1` with `build_test_result/2`:

```elixir
  defp build_test_result(_output, {:error, reason}), do: {:error, inspect(reason)}

  defp build_test_result(:xlsx, {:ok, result}) do
    case Excel.to_sheets(result) do
      {:ok, sheets} -> {:table, sheets}
      :error -> {:json_fallback, Jason.encode!(result, pretty: true)}
    end
  end

  defp build_test_result(_output, {:ok, result}), do: {:json, Jason.encode!(result, pretty: true)}
```

- [ ] **Step 4: Update `form.html.heex`**

Replace this block (currently lines 71-74):

```heex
    <div :if={@test_result} class="mt-4">
      <p :if={elem(@test_result, 0) == :error} class="text-error font-semibold">{gettext("Error")}</p>
      <pre class="bg-base-200 p-4 rounded overflow-x-auto text-sm">{elem(@test_result, 1)}</pre>
    </div>
```

with:

```heex
    <div :if={@test_result} class="mt-4">
      <%= case @test_result do %>
        <% {:error, message} -> %>
          <p class="text-error font-semibold">{gettext("Error")}</p>
          <pre class="bg-base-200 p-4 rounded overflow-x-auto text-sm">{message}</pre>
        <% {:json, json} -> %>
          <pre class="bg-base-200 p-4 rounded overflow-x-auto text-sm">{json}</pre>
        <% {:json_fallback, json} -> %>
          <p class="text-warning text-sm mb-2">
            {gettext("The result doesn't have a table shape, showing raw JSON instead.")}
          </p>
          <pre class="bg-base-200 p-4 rounded overflow-x-auto text-sm">{json}</pre>
        <% {:table, sheets} -> %>
          <div :for={sheet <- sheets} class="mb-6 last:mb-0">
            <h4 :if={length(sheets) > 1} class="font-semibold mb-1">{sheet["name"]}</h4>
            <div class="overflow-x-auto">
              <table class="table table-zebra">
                <thead>
                  <tr>
                    <th :for={header <- sheet["headers"]}>{header}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- sheet["rows"]}>
                    <td :for={cell <- row}>{cell}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
      <% end %>
    </div>
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test apps/conta_web/test/conta_web/live/filter_live_test.exs`
Expected: all tests in the file pass, including the two new ones and the pre-existing `"test-runs the Lua code without dispatching anything"` test (which uses `output: "json"` and must still render the JSON `<pre>` unchanged).

- [ ] **Step 6: Extract the new gettext string**

Run: `cd apps/conta_web && mix gettext.extract --merge && cd ../..`
Expected: `priv/gettext/default.pot` and `priv/gettext/en/LC_MESSAGES/default.po` gain an entry for `"The result doesn't have a table shape, showing raw JSON instead."`. Review the diff — it should only add this one new msgid, not touch unrelated entries.

- [ ] **Step 7: Run the full `conta_web` test suite to check for regressions**

Run: `mix test apps/conta_web/test`
Expected: same pass count as before this change (no new failures).

- [ ] **Step 8: Commit**

```bash
git add apps/conta_web/lib/conta_web/live/filter_live/form.ex apps/conta_web/lib/conta_web/live/filter_live/form.html.heex apps/conta_web/test/conta_web/live/filter_live_test.exs apps/conta_web/priv/gettext
git commit -m "Render filter test-run preview as a table when output is xlsx"
```

---

## Manual verification (after both tasks)

- [ ] Start the app (`mix phx.server` from repo root, or the project's usual dev command).
- [ ] Open `/automation/filters/new`, set Output to "Excel", enter Lua code that returns a list of records (e.g. `return {{name = "Alice", amount = 100}, {name = "Bob", amount = 200}}`), click "Run" under "Test data".
- [ ] Confirm an HTML table appears with "name"/"amount" columns and the two rows — not a JSON blob.
- [ ] Change Output back to "JSON" (no need to save, just for one more test-run), click "Run" again with the same code.
- [ ] Confirm the JSON `<pre>` output reappears (unchanged old behavior for `:json`).
- [ ] Switch back to Output "Excel" and click "Run" with code that returns a non-table value (e.g. `return 42`).
- [ ] Confirm the fallback warning message appears above the raw JSON `42`.
