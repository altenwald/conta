# Monaco Lua Editor for Filters/Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a full CRUD web UI (LiveView) for Filters and Shortcuts, with a Monaco code editor for their Lua source, a "test data" panel to run that code against sample params without dispatching real commands, and a Save action that persists via the existing `SetFilter`/`SetShortcut` commands.

**Architecture:** Two new full-page LiveView pairs (`FilterLive.Index`/`FilterLive.Form`, `ShortcutLive.Index`/`ShortcutLive.Form`) mounted under a new "Automation" nav section, backed by two new `Conta.Automator` functions (`test_run_filter/3`, `test_run_shortcut/3`) that reuse the existing private `validate_params/2`/`cast/2` logic but call `Lua.run/2` directly instead of dispatching commands. Monaco is loaded via a small local npm step (vendored into the esbuild bundle, no CDN) and wired to the LiveView form through a `phx-hook` that syncs into a hidden form field.

**Tech Stack:** Elixir/Phoenix LiveView, Ecto embedded schemas, Luerl (via `Conta.Automator.Lua`), monaco-editor (npm), esbuild.

**Spec:** `docs/superpowers/specs/2026-07-07-monaco-lua-editor-design.md`

---

## Before you start

Read `docs/superpowers/specs/2026-07-07-monaco-lua-editor-design.md` for the full rationale. Key facts you'll rely on throughout:

- `Conta.Automator.Lua.run/2` (`apps/conta/lib/conta/automator/lua.ex:35`) is public, takes `code` and an enumerable of `{name, value}` pairs, returns `{:ok, result}` or `{:error, message}`.
- `Conta.Automator.cast/2` (`apps/conta/lib/conta/automator.ex:318-324`) is **public** and accepts a `%Filter{}` or `%Shortcut{}` struct plus a raw params map; it returns a list of `{name, value}` tuples.
- `Conta.Automator.validate_params/2` is **private**, but the new functions live in the same module (`Conta.Automator`) so they can call it directly.
- `automator` is always the constant `"automator"` and `language` is always `:lua` in this UI — both are hidden from the user (see spec section "Alcance").
- The app uses `ContaWeb.AppComponents` (not `ContaWeb.CoreComponents`) for `input/1`, `button/1`, `table/1`, `simple_form/1`, etc. — see `apps/conta_web/lib/conta_web/components/app_components.ex`.
- All existing CRUD LiveViews use a modal-over-index pattern; this feature deliberately uses full standalone pages instead (per user decision), so don't copy the modal wiring from `ContactLive`/`EntryLive`.

---

## Task 1: `Automator` context — test-run functions

**Files:**
- Modify: `apps/conta/lib/conta/automator.ex`
- Modify: `apps/conta/test/conta/automator_context_test.exs`

- [ ] **Step 1: Write the failing tests**

Add this new `describe` block at the end of `apps/conta/test/conta/automator_context_test.exs`, right before the final `end` of the module:

```elixir
  describe "new_set_filter/0 and new_set_shortcut/0" do
    test "new_set_filter/0 defaults automator and language" do
      set_filter = Automator.new_set_filter()
      assert set_filter.automator == "automator"
      assert set_filter.language == :lua
      assert set_filter.params == []
    end

    test "new_set_shortcut/0 defaults automator and language" do
      set_shortcut = Automator.new_set_shortcut()
      assert set_shortcut.automator == "automator"
      assert set_shortcut.language == :lua
      assert set_shortcut.params == []
    end
  end

  describe "test_run_filter/3" do
    test "runs Lua code against test params and returns the decoded result" do
      params_defs = [
        %Param{name: "a", type: :integer},
        %Param{name: "b", type: :integer}
      ]

      assert {:ok, 30} =
               Automator.test_run_filter(params_defs, "return a + b", %{"a" => "10", "b" => "20"})
    end

    test "returns a validation error when a required param is missing" do
      params_defs = [%Param{name: "a", type: :integer}]

      assert {:error, %{"a" => ["can't be blank"]}} =
               Automator.test_run_filter(params_defs, "return a", %{})
    end

    test "returns a Lua error for invalid code" do
      assert {:error, _reason} = Automator.test_run_filter([], "this is not lua", %{})
    end
  end

  describe "test_run_shortcut/3" do
    test "returns the commands the Lua code would generate, without dispatching them" do
      params_defs = [%Param{name: "amount", type: :money}]

      code = ~S"""
      return {status = "ok", commands = {{type = "transaction", data = {foo = "bar"}}}}
      """

      assert {:ok, [%{"type" => "transaction", "data" => %{"foo" => "bar"}}]} =
               Automator.test_run_shortcut(params_defs, code, %{"amount" => "100"})
    end

    test "returns an error when the Lua code doesn't return the expected shape" do
      assert {:error, {:invalid_code_return, 42}} = Automator.test_run_shortcut([], "return 42", %{})
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/conta && mix test test/conta/automator_context_test.exs`
Expected: FAIL — `Automator.new_set_filter/0`, `Automator.new_set_shortcut/0`, `Automator.test_run_filter/3`, and `Automator.test_run_shortcut/3` are undefined.

- [ ] **Step 3: Implement the functions**

In `apps/conta/lib/conta/automator.ex`, add these public functions right after `get_filter!/2` (around line 140, before `def run_shortcut`):

```elixir
  def new_set_filter(automator \\ @default_automator) do
    %SetFilter{automator: automator, language: :lua, output: :json, code: "-- Lua code\n", params: []}
  end

  def new_set_shortcut(automator \\ @default_automator) do
    %SetShortcut{automator: automator, language: :lua, code: "-- Lua code\n", params: []}
  end

  def test_run_filter(params_defs, code, test_params) do
    filter = %Filter{params: to_projector_params(params_defs), code: code, language: :lua}

    with :ok <- validate_params(filter.params, test_params) do
      Lua.run(code, cast(filter, test_params))
    end
  end

  def test_run_shortcut(params_defs, code, test_params) do
    shortcut = %Shortcut{params: to_projector_params(params_defs), code: code, language: :lua}

    with :ok <- validate_params(shortcut.params, test_params),
         {:ok, %{"status" => "ok", "commands" => commands}} when is_list(commands) <-
           Lua.run(code, cast(shortcut, test_params)) do
      {:ok, commands}
    else
      {:error, _} = error -> error
      {:ok, return} -> {:error, {:invalid_code_return, return}}
    end
  end

  defp to_projector_params(params) do
    Enum.map(params, fn param -> %Param{name: param.name, type: param.type, options: param.options} end)
  end
```

This module already aliases `Conta.Command.SetFilter` and `Conta.Command.SetShortcut` (lines 12 and 14) — no new aliases needed.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/conta && mix test test/conta/automator_context_test.exs`
Expected: PASS (all tests green, including the pre-existing ones).

- [ ] **Step 5: Commit**

```bash
git add apps/conta/lib/conta/automator.ex apps/conta/test/conta/automator_context_test.exs
git commit -m "Add Automator.test_run_filter/3 and test_run_shortcut/3 for dry-run previews"
```

---

## Task 2: Test fixtures for filters

**Files:**
- Modify: `apps/conta/test/support/fixtures/automator_fixtures.ex`

- [ ] **Step 1: Add a `filter_factory` mirroring the existing `shortcut_factory`**

In `apps/conta/test/support/fixtures/automator_fixtures.ex`, add after `shortcut_param_factory/0`:

```elixir
  def filter_factory do
    %Conta.Projector.Automator.Filter{
      name: "unpaid invoices",
      automator: "automator",
      description: "list unpaid invoices",
      type: :all,
      output: :json,
      code: "-- Lua code\n",
      language: :lua
    }
  end

  def filter_param_factory do
    %Conta.Projector.Automator.Param{
      name: "from_date",
      type: :date
    }
  end
```

- [ ] **Step 2: Verify it compiles and existing tests still pass**

Run: `cd apps/conta && mix test test/conta/automator_context_test.exs`
Expected: PASS (no behavior changed yet, just a new unused-so-far factory).

- [ ] **Step 3: Commit**

```bash
git add apps/conta/test/support/fixtures/automator_fixtures.ex
git commit -m "Add filter_factory/filter_param_factory test fixtures"
```

---

## Task 3: npm + Monaco asset pipeline

**Files:**
- Create: `apps/conta_web/assets/package.json`
- Modify: `apps/conta_web/mix.exs`

- [ ] **Step 1: Create the package.json**

Create `apps/conta_web/assets/package.json`:

```json
{
  "name": "conta_web_assets",
  "private": true,
  "dependencies": {
    "monaco-editor": "^0.52.0"
  }
}
```

- [ ] **Step 2: Wire npm install into `mix assets.setup`**

In `apps/conta_web/mix.exs`, modify the `aliases/0` function's `"assets.setup"` entry:

```elixir
      "assets.setup": [
        "tailwind.install --if-missing",
        "esbuild.install --if-missing",
        "cmd --cd assets npm install"
      ],
```

- [ ] **Step 3: Confirm node_modules is already ignored**

`apps/conta_web/.gitignore:36` already has `/assets/node_modules/`, which covers the new `apps/conta_web/assets/node_modules/` directory — no `.gitignore` change needed.

- [ ] **Step 4: Run the setup and verify monaco-editor is installed**

Run: `mix assets.setup`
Expected: `npm install` runs inside `apps/conta_web/assets` and creates `apps/conta_web/assets/node_modules/monaco-editor/`.

Run: `ls apps/conta_web/assets/node_modules/monaco-editor/package.json`
Expected: file exists.

- [ ] **Step 5: Commit**

```bash
git add apps/conta_web/assets/package.json apps/conta_web/mix.exs
git commit -m "Add monaco-editor npm dependency for the Lua code editor"
```

Note: `apps/conta_web/assets/package-lock.json` will also be created by `npm install` — add it too (`git add apps/conta_web/assets/package-lock.json`) so the dependency is pinned for other machines/CI.

---

## Task 4: Monaco JS hook

**Files:**
- Create: `apps/conta_web/assets/js/hooks/monaco_editor.js`
- Create: `apps/conta_web/assets/js/hooks/index.js`
- Modify: `apps/conta_web/assets/js/app.js`
- Modify: `config/config.exs` (discovered during implementation: monaco-editor's codicon font CSS references a `.ttf` file esbuild has no default loader for; add `--loader:.ttf=file` to `bundle_app`'s args only, leave `bundle_print` untouched)

- [ ] **Step 1: Create the hook**

Create `apps/conta_web/assets/js/hooks/monaco_editor.js`:

```javascript
import * as monaco from "monaco-editor";

const MonacoEditor = {
  mounted() {
    const targetId = this.el.dataset.target;
    this.hiddenInput = document.getElementById(targetId);
    const initialValue = this.el.dataset.value || "";
    const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;

    this.editor = monaco.editor.create(this.el, {
      value: initialValue,
      language: "lua",
      theme: isDark ? "vs-dark" : "vs",
      automaticLayout: true,
      minimap: { enabled: false },
    });

    this.debounceTimer = null;

    this.editor.onDidChangeModelContent(() => {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = setTimeout(() => {
        this.hiddenInput.value = this.editor.getValue();
        this.hiddenInput.dispatchEvent(new Event("input", { bubbles: true }));
      }, 300);
    });
  },

  destroyed() {
    clearTimeout(this.debounceTimer);
    this.editor?.dispose();
  },
};

export default MonacoEditor;
```

- [ ] **Step 2: Create the hooks barrel**

Create `apps/conta_web/assets/js/hooks/index.js`:

```javascript
import MonacoEditor from "./monaco_editor";

export default {
  MonacoEditor,
};
```

- [ ] **Step 3: Register hooks in the LiveSocket**

In `apps/conta_web/assets/js/app.js`, add the import near the other imports (after `import topbar from "../vendor/topbar";`):

```javascript
import Hooks from "./hooks";
```

Then change the `LiveSocket` construction:

```javascript
let liveSocket = new LiveSocket("/live", Socket, { hooks: Hooks, params: { _csrf_token: csrfToken } });
```

- [ ] **Step 4: Build assets and verify no errors**

Run: `mix assets.build`
Expected: esbuild completes without errors and bundles `monaco-editor` into `priv/static/assets/app.js` (the bundle size will grow noticeably — that's expected).

- [ ] **Step 5: Commit**

```bash
git add apps/conta_web/assets/js/hooks apps/conta_web/assets/js/app.js
git commit -m "Add MonacoEditor LiveView hook and register it on the LiveSocket"
```

---

## Task 5: Shared UI components for automator forms

**Files:**
- Create: `apps/conta_web/lib/conta_web/components/automator_components.ex`

- [ ] **Step 1: Create the component module**

Create `apps/conta_web/lib/conta_web/components/automator_components.ex`:

```elixir
defmodule ContaWeb.AutomatorComponents do
  @moduledoc """
  Shared components for the Filter/Shortcut Lua editor forms
  (`ContaWeb.FilterLive.Form` and `ContaWeb.ShortcutLive.Form`).
  """
  use Phoenix.Component
  use Gettext, backend: ContaWeb.Gettext

  @doc """
  Renders the Monaco-backed Lua code editor bound to a form field.

  The editor container has `phx-update="ignore"` so LiveView never
  touches its DOM after mount — all syncing back to the form happens
  through the hidden input via the `MonacoEditor` JS hook.
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :height, :string, default: "420px"

  def monaco_editor(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <span class="label mb-1">{gettext("Code (Lua)")}</span>
      <div
        id={"#{@field.id}-editor"}
        phx-hook="MonacoEditor"
        phx-update="ignore"
        data-target={@field.id}
        data-value={@field.value}
        style={"height: #{@height}; border: 1px solid oklch(var(--bc)/0.2);"}
      >
      </div>
      <input type="hidden" id={@field.id} name={@field.name} value={@field.value} />
    </div>
    """
  end

  @doc "The `Param.type` choices shared by the params-definition editor."
  def param_type_options do
    [
      {"string", "string"},
      {"date", "date"},
      {"integer", "integer"},
      {"money", "money"},
      {"currency", "currency"},
      {"options", "options"},
      {"account_name", "account_name"},
      {"table", "table"}
    ]
  end

  @doc """
  Renders one input control for a "test data" value, based on the
  `Param`'s `:type`. Used by the test-run panel in `FilterLive.Form`/
  `ShortcutLive.Form` — one of these per parameter defined on the
  filter/shortcut being edited.
  """
  attr :param, :map, required: true

  def test_param_input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <span class="label mb-1">{@param.name}</span>
      {render_control(assigns)}
    </div>
    """
  end

  defp render_control(%{param: %{type: :options}} = assigns) do
    ~H"""
    <select name={"test_params[#{@param.name}]"} class="w-full select select-bordered">
      <option :for={opt <- @param.options || []} value={opt}>{opt}</option>
    </select>
    """
  end

  defp render_control(%{param: %{type: :currency}} = assigns) do
    assigns =
      assign(assigns, :currencies, Money.Currency.all() |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort())

    ~H"""
    <select name={"test_params[#{@param.name}]"} class="w-full select select-bordered">
      <option :for={currency <- @currencies} value={currency}>{currency}</option>
    </select>
    """
  end

  defp render_control(%{param: %{type: :date}} = assigns) do
    ~H"""
    <input type="date" name={"test_params[#{@param.name}]"} class="w-full input input-bordered" />
    """
  end

  defp render_control(%{param: %{type: type}} = assigns) when type in [:integer, :money] do
    ~H"""
    <input type="number" name={"test_params[#{@param.name}]"} class="w-full input input-bordered" />
    """
  end

  defp render_control(%{param: %{type: :table}} = assigns) do
    ~H"""
    <textarea name={"test_params[#{@param.name}]"} class="w-full textarea textarea-bordered" rows="3"></textarea>
    """
  end

  defp render_control(assigns) do
    ~H"""
    <input type="text" name={"test_params[#{@param.name}]"} class="w-full input input-bordered" />
    """
  end
end
```

Note: `param.options` in `render_control` may be `nil` for a freshly-added, not-yet-saved param — the `|| []` guard on the `:options` branch already handles that.

- [ ] **Step 2: Verify it compiles**

Run: `cd apps/conta_web && mix compile`
Expected: compiles with no errors or warnings about `ContaWeb.AutomatorComponents`.

- [ ] **Step 3: Commit**

```bash
git add apps/conta_web/lib/conta_web/components/automator_components.ex
git commit -m "Add shared Monaco editor and test-param-input components"
```

---

## Task 6: Routes and navigation

**Files:**
- Modify: `apps/conta_web/lib/conta_web/router.ex`
- Modify: `apps/conta_web/lib/conta_web/components/layouts/app.html.heex`

- [ ] **Step 1: Add the routes**

In `apps/conta_web/lib/conta_web/router.ex`, inside the `live_session :require_authenticated_user` block (after the `directories/contacts` scope, before the closing `end` of that scope — i.e. right after line 178's `end` for the contacts scope and before line 179's `end` for the live_session):

```elixir
      scope "/automation/filters/" do
        live "/", FilterLive.Index, :index
        live "/new", FilterLive.Form, :new
        live "/:id/edit", FilterLive.Form, :edit
      end

      scope "/automation/shortcuts/" do
        live "/", ShortcutLive.Index, :index
        live "/new", ShortcutLive.Form, :new
        live "/:id/edit", ShortcutLive.Form, :edit
      end
```

- [ ] **Step 2: Add the navbar entry**

In `apps/conta_web/lib/conta_web/components/layouts/app.html.heex`, after the `<.navbar_dropdown name={gettext("Directories")}>...</.navbar_dropdown>` block (following the same pattern as `Ledger`/`Books`/`Directories`), add:

```heex
    <.navbar_dropdown name={gettext("Automation")}>
      <.navbar_item href={~p"/automation/filters"}>{gettext("Filters")}</.navbar_item>
      <.navbar_item href={~p"/automation/shortcuts"}>{gettext("Shortcuts")}</.navbar_item>
    </.navbar_dropdown>
```

- [ ] **Step 3: Verify the app still compiles**

Run: `cd apps/conta_web && mix compile`
Expected: FAILS at this point — `FilterLive.Index`, `FilterLive.Form`, `ShortcutLive.Index`, `ShortcutLive.Form` don't exist yet. That's expected; they're built in the next tasks. Confirm the *only* errors are "module ContaWeb.FilterLive.Index is not available" (or similar) and nothing else (e.g. no typo in the heex or router syntax).

- [ ] **Step 4: Commit**

```bash
git add apps/conta_web/lib/conta_web/router.ex apps/conta_web/lib/conta_web/components/layouts/app.html.heex
git commit -m "Add routes and nav entry for Filters/Shortcuts automation pages"
```

(This commit will not compile in isolation until Task 7-10 land — that's fine for a local multi-commit branch; if you squash/rebase before merging, consider folding it into the last of those tasks instead.)

---

## Task 7: `FilterLive.Index`

**Files:**
- Create: `apps/conta_web/lib/conta_web/live/filter_live/index.ex`
- Create: `apps/conta_web/lib/conta_web/live/filter_live/index.html.heex`
- Create: `apps/conta_web/test/conta_web/live/filter_live_test.exs`

- [ ] **Step 1: Write the failing test**

Create `apps/conta_web/test/conta_web/live/filter_live_test.exs`:

```elixir
defmodule ContaWeb.FilterLiveTest do
  use ContaWeb.ConnCase

  import Phoenix.LiveViewTest
  import Conta.AutomatorFixtures

  alias Conta.AccountsFixtures

  setup do
    user = AccountsFixtures.insert(:user) |> AccountsFixtures.confirm_user()
    %{user: user}
  end

  describe "Index" do
    test "lists all filters", %{conn: conn, user: user} do
      filter = insert(:filter, %{name: "my filter"})
      conn = log_in_user(conn, user)

      {:ok, _index_live, html} = live(conn, ~p"/automation/filters")

      assert html =~ "my filter"
      refute html =~ filter.id
    end

    test "deletes filter in listing", %{conn: conn, user: user} do
      filter = insert(:filter, %{name: "to be removed"})
      conn = log_in_user(conn, user)

      {:ok, index_live, _html} = live(conn, ~p"/automation/filters")

      assert index_live
             |> element("#automator_filters-#{filter.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#automator_filters-#{filter.id}")
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/conta_web && mix test test/conta_web/live/filter_live_test.exs`
Expected: FAIL — no route/module for `FilterLive.Index` yet (the router change from Task 6 references a module that doesn't exist).

- [ ] **Step 3: Implement the LiveView**

Create `apps/conta_web/lib/conta_web/live/filter_live/index.ex`:

```elixir
defmodule ContaWeb.FilterLive.Index do
  use ContaWeb, :live_view

  require Logger

  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Automator
  alias Conta.Projector.Automator.Filter

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :automator_filters, Automator.list_filters())}
  end

  @impl true
  def handle_event("delete", %{"id" => id, "dom_id" => dom_id}, socket) do
    with %Filter{} = filter <- Automator.get_filter(id),
         :ok <- dispatch(Automator.get_remove_filter(filter)) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Filter removed successfully"))
       |> stream_delete_by_dom_id(:automator_filters, dom_id)}
    else
      error ->
        Logger.error("cannot remove filter: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, gettext("Cannot remove the filter"))}
    end
  end
end
```

Create `apps/conta_web/lib/conta_web/live/filter_live/index.html.heex`:

```heex
<section class="py-6">
  <.breadcrumbs>
    <:breadcrumb label={gettext("Dashboard")} href={~p"/"} />
    <:breadcrumb label={gettext("Filters")} href={~p"/automation/filters"} />
  </.breadcrumbs>

  <div class="card bg-base-100 shadow-xl border border-base-200 mt-6">
    <div class="card-body p-0">
      <div class="p-4 flex justify-between items-center border-b border-base-200">
        <h1 class="text-lg font-semibold">{gettext("Filters")}</h1>
        <.link patch={~p"/automation/filters/new"} class="btn btn-primary">
          <.icon name="hero-plus-circle" class="w-5 h-5 mr-2" />
          <span>{gettext("New Filter")}</span>
        </.link>
      </div>
      <div class="overflow-x-auto">
        <.table id="automator_filters" rows={@streams.automator_filters}>
          <:action :let={{_id, filter}}>
            <.link class="btn btn-ghost btn-sm" patch={~p"/automation/filters/#{filter}/edit"} title={gettext("Edit")}>
              <.icon name="hero-pencil" class="w-4 h-4" />
            </.link>
          </:action>
          <:action :let={{id, filter}}>
            <.link
              phx-click={JS.push("delete", value: %{id: filter.id, dom_id: id})}
              class="btn btn-error btn-outline btn-sm"
              data-confirm={gettext("Are you sure?")}
              title={gettext("Delete")}
            >
              {gettext("Delete")}
            </.link>
          </:action>
          <:col :let={{_id, filter}} label={gettext("Name")}>{filter.name}</:col>
          <:col :let={{_id, filter}} label={gettext("Description")}>{filter.description}</:col>
          <:col :let={{_id, filter}} label={gettext("Type")}>{filter.type}</:col>
          <:col :let={{_id, filter}} label={gettext("Output")}>{filter.output}</:col>
        </.table>
      </div>
    </div>
  </div>
</section>
```

Note this template uses `patch` for now (to `/automation/filters/new` and `/automation/filters/#{filter}/edit`), which live-navigates to `FilterLive.Form` — since that's a *different* LiveView module than `FilterLive.Index`, Phoenix LiveView will actually do a full remount (equivalent to `navigate`) automatically when the target module differs, so `patch` vs `navigate` both work here; using `patch` keeps consistency with existing list pages but you may use `navigate` for clarity. Also add `alias Phoenix.LiveView.JS` — actually `JS` is available automatically via `ContaWeb.CoreComponents`/`use ContaWeb, :html` common imports (confirm in step 4 below; other templates like `contact_live/index.html.heex` use `JS.push` without a local alias, so it's already imported project-wide).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/conta_web && mix test test/conta_web/live/filter_live_test.exs`
Expected: PASS. If you get a `JS` undefined error in the heex, check how `contact_live/index.html.heex` gets access to it (it's imported through the `ContaWeb` web module's `:html` using-macro) and mirror that import in `filter_live/index.html.heex`'s parent module if needed — no extra import should actually be required since `use ContaWeb, :live_view` already pulls in the same html helpers as `ContactLive.Index`.

- [ ] **Step 5: Commit**

```bash
git add apps/conta_web/lib/conta_web/live/filter_live/index.ex apps/conta_web/lib/conta_web/live/filter_live/index.html.heex apps/conta_web/test/conta_web/live/filter_live_test.exs
git commit -m "Add FilterLive.Index (list and delete filters)"
```

---

## Task 8: `FilterLive.Form` (general data + Monaco editor + test panel)

**Files:**
- Create: `apps/conta_web/lib/conta_web/live/filter_live/form.ex`
- Create: `apps/conta_web/lib/conta_web/live/filter_live/form.html.heex`
- Modify: `apps/conta_web/test/conta_web/live/filter_live_test.exs`

- [ ] **Step 1: Write the failing tests**

Add to `apps/conta_web/test/conta_web/live/filter_live_test.exs`, inside the module, after the `describe "Index"` block:

```elixir
  describe "Form" do
    test "creates a new filter", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/new")

      assert form_live
             |> form("#filter-form", set_filter: %{name: "", output: "json"})
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _index_live, html} =
        form_live
        |> form("#filter-form", set_filter: %{name: "brand new filter", output: "json"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/automation/filters")

      assert html =~ "Filter saved successfully"
      assert html =~ "brand new filter"
    end

    test "edits an existing filter", %{conn: conn, user: user} do
      filter = insert(:filter, %{name: "old name"})
      conn = log_in_user(conn, user)

      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/#{filter}/edit")

      {:ok, _index_live, html} =
        form_live
        |> form("#filter-form", set_filter: %{name: "new name"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/automation/filters")

      assert html =~ "Filter saved successfully"
      assert html =~ "new name"
    end

    test "test-runs the Lua code without dispatching anything", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/new")

      form_live
      |> form("#filter-form", set_filter: %{name: "sum filter", code: "return 1 + 1", output: "json"})
      |> render_change()

      html = form_live |> element("form[phx-submit=test_run]") |> render_submit()

      assert html =~ "2"
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/conta_web && mix test test/conta_web/live/filter_live_test.exs`
Expected: FAIL — `FilterLive.Form` doesn't exist yet.

- [ ] **Step 3: Implement the LiveView**

Create `apps/conta_web/lib/conta_web/live/filter_live/form.ex`:

```elixir
defmodule ContaWeb.FilterLive.Form do
  use ContaWeb, :live_view

  import Ecto.Changeset, only: [get_field: 2]
  import Conta.Commanded.Application, only: [dispatch: 1]
  import ContaWeb.AutomatorComponents

  require Logger

  alias Conta.Automator
  alias Conta.Command.SetFilter

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :test_result, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    set_filter = Automator.new_set_filter()

    socket
    |> assign(:page_title, gettext("New Filter"))
    |> assign(:set_filter, set_filter)
    |> assign(:form_params, %{})
    |> assign_form(SetFilter.changeset(set_filter, %{}))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    set_filter = Automator.get_set_filter(id)

    socket
    |> assign(:page_title, gettext("Edit Filter"))
    |> assign(:set_filter, set_filter)
    |> assign(:form_params, %{})
    |> assign_form(SetFilter.changeset(set_filter, %{}))
  end

  @impl true
  def handle_event("validate", %{"set_filter" => params}, socket) do
    changeset =
      socket.assigns.set_filter
      |> SetFilter.changeset(force_constants(params))
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:form_params, params) |> assign_form(changeset)}
  end

  def handle_event("add_param", _params, socket) do
    params =
      Map.update(socket.assigns.form_params, "params", %{"0" => %{}}, fn existing ->
        Map.put(existing, to_string(map_size(existing)), %{})
      end)

    changeset =
      socket.assigns.set_filter
      |> SetFilter.changeset(force_constants(params))
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:form_params, params) |> assign_form(changeset)}
  end

  def handle_event("del_param", %{"index" => index}, socket) do
    params = Map.update(socket.assigns.form_params, "params", %{}, &Map.delete(&1, index))

    changeset =
      socket.assigns.set_filter
      |> SetFilter.changeset(force_constants(params))
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:form_params, params) |> assign_form(changeset)}
  end

  def handle_event("save", %{"set_filter" => params}, socket) do
    changeset = SetFilter.changeset(socket.assigns.set_filter, force_constants(params))

    if changeset.valid? and dispatch(SetFilter.to_command(changeset)) == :ok do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Filter saved successfully"))
       |> push_navigate(to: ~p"/automation/filters")}
    else
      Logger.debug("changeset errors: #{inspect(changeset.errors)}")

      {:noreply,
       socket
       |> assign(:form_params, params)
       |> assign_form(Map.put(changeset, :action, :validate))}
    end
  end

  def handle_event("test_run", %{"test_params" => raw_test_params}, socket) do
    changeset = socket.assigns.form.source
    code = get_field(changeset, :code) || ""
    params_defs = get_field(changeset, :params) || []
    test_params = cast_test_params(params_defs, raw_test_params)

    result = Automator.test_run_filter(params_defs, code, test_params)

    {:noreply, assign(socket, :test_result, format_test_result(result))}
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
```

Create `apps/conta_web/lib/conta_web/live/filter_live/form.html.heex`:

```heex
<section class="py-6">
  <.breadcrumbs>
    <:breadcrumb label={gettext("Dashboard")} href={~p"/"} />
    <:breadcrumb label={gettext("Filters")} href={~p"/automation/filters"} />
    <:breadcrumb label={@page_title} href="#" />
  </.breadcrumbs>

  <.simple_form for={@form} id="filter-form" phx-change="validate" phx-submit="save">
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
      <div class="card bg-base-100 shadow-xl border border-base-200 p-4">
        <h2 class="font-semibold mb-2">{gettext("General data")}</h2>
        <.input field={@form[:name]} type="text" label={gettext("Name")} />
        <.input field={@form[:description]} type="text" label={gettext("Description")} />
        <.input
          field={@form[:type]}
          type="select"
          label={gettext("Type")}
          options={[
            {gettext("All"), "all"},
            {gettext("Invoice"), "invoice"},
            {gettext("Expense"), "expense"},
            {gettext("Entry"), "entry"}
          ]}
        />
        <.input
          field={@form[:output]}
          type="select"
          label={gettext("Output")}
          options={[{gettext("JSON"), "json"}, {gettext("Excel"), "xlsx"}]}
        />

        <div class="flex items-center justify-between mt-4 mb-2">
          <h3 class="font-semibold">{gettext("Parameters")}</h3>
          <.button type="button" phx-click="add_param" class="btn-sm">
            {gettext("Add parameter")}
          </.button>
        </div>

        <.inputs_for :let={p} field={@form[:params]}>
          <div class="grid grid-cols-[1fr_1fr_1fr_auto] gap-2 items-end mb-2">
            <.input field={p[:name]} label={gettext("Name")} />
            <.input field={p[:type]} type="select" label={gettext("Type")} options={param_type_options()} />
            <.input field={p[:options]} label={gettext("Options (comma separated)")} />
            <.button type="button" phx-click="del_param" phx-value-index={p.index} class="btn-sm btn-error">
              {gettext("Remove")}
            </.button>
          </div>
        </.inputs_for>
      </div>

      <div class="card bg-base-100 shadow-xl border border-base-200 p-4">
        <.monaco_editor field={@form[:code]} />
      </div>
    </div>

    <:actions>
      <.button class="btn-primary" phx-disable-with={gettext("Saving...")}>
        {gettext("Save")}
      </.button>
      <.link navigate={~p"/automation/filters"} class="btn">{gettext("Cancel")}</.link>
    </:actions>
  </.simple_form>

  <div class="card bg-base-100 shadow-xl border border-base-200 p-4 mt-6">
    <h2 class="font-semibold mb-2">{gettext("Test data")}</h2>
    <form phx-submit="test_run">
      <.test_param_input :for={param <- @params_defs} param={param} />
      <button type="submit" class="btn btn-secondary mt-2">{gettext("Run")}</button>
    </form>

    <div :if={@test_result} class="mt-4">
      <p :if={elem(@test_result, 0) == :error} class="text-error font-semibold">{gettext("Error")}</p>
      <pre class="bg-base-200 p-4 rounded overflow-x-auto text-sm">{elem(@test_result, 1)}</pre>
    </div>
  </div>
</section>
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/conta_web && mix test test/conta_web/live/filter_live_test.exs`
Expected: PASS. `monaco_editor/1`, `test_param_input/1`, and `param_type_options/0` are available in the `.heex` template via the `import ContaWeb.AutomatorComponents` already added in the module above.

If the "test-runs the Lua code" test fails because `<pre>` content isn't found, double check `format_test_result/1` actually produces a string containing `"2"` — `Jason.encode!(2, pretty: true)` returns `"2"`, so this should match directly.

- [ ] **Step 5: Manually exercise the Monaco editor in a browser**

Run: `mix phx.server`, log in, visit `/automation/filters/new`, confirm the Monaco editor renders with Lua syntax highlighting, typing updates the hidden `code` field (check via browser devtools that the hidden input's value changes), and saving persists correctly (verify via `GET /api/v1/automator/filters` after saving, per the spec's manual test plan).

- [ ] **Step 6: Commit**

```bash
git add apps/conta_web/lib/conta_web/live/filter_live/form.ex apps/conta_web/lib/conta_web/live/filter_live/form.html.heex apps/conta_web/test/conta_web/live/filter_live_test.exs
git commit -m "Add FilterLive.Form with Monaco editor and test-run panel"
```

---

## Task 9: `ShortcutLive.Index`

**Files:**
- Create: `apps/conta_web/lib/conta_web/live/shortcut_live/index.ex`
- Create: `apps/conta_web/lib/conta_web/live/shortcut_live/index.html.heex`
- Create: `apps/conta_web/test/conta_web/live/shortcut_live_test.exs`

This mirrors Task 7 exactly, minus the `type`/`output` columns (shortcuts don't have them).

- [ ] **Step 1: Write the failing test**

Create `apps/conta_web/test/conta_web/live/shortcut_live_test.exs`:

```elixir
defmodule ContaWeb.ShortcutLiveTest do
  use ContaWeb.ConnCase

  import Phoenix.LiveViewTest
  import Conta.AutomatorFixtures

  alias Conta.AccountsFixtures

  setup do
    user = AccountsFixtures.insert(:user) |> AccountsFixtures.confirm_user()
    %{user: user}
  end

  describe "Index" do
    test "lists all shortcuts", %{conn: conn, user: user} do
      shortcut = insert(:shortcut, %{name: "my shortcut"})
      conn = log_in_user(conn, user)

      {:ok, _index_live, html} = live(conn, ~p"/automation/shortcuts")

      assert html =~ "my shortcut"
      refute html =~ shortcut.id
    end

    test "deletes shortcut in listing", %{conn: conn, user: user} do
      shortcut = insert(:shortcut, %{name: "to be removed"})
      conn = log_in_user(conn, user)

      {:ok, index_live, _html} = live(conn, ~p"/automation/shortcuts")

      assert index_live
             |> element("#automator_shortcuts-#{shortcut.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#automator_shortcuts-#{shortcut.id}")
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/conta_web && mix test test/conta_web/live/shortcut_live_test.exs`
Expected: FAIL — module doesn't exist.

- [ ] **Step 3: Implement the LiveView**

Create `apps/conta_web/lib/conta_web/live/shortcut_live/index.ex`:

```elixir
defmodule ContaWeb.ShortcutLive.Index do
  use ContaWeb, :live_view

  require Logger

  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Automator
  alias Conta.Projector.Automator.Shortcut

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :automator_shortcuts, Automator.list_shortcuts())}
  end

  @impl true
  def handle_event("delete", %{"id" => id, "dom_id" => dom_id}, socket) do
    with %Shortcut{} = shortcut <- Automator.get_shortcut(id),
         :ok <- dispatch(Automator.get_remove_shortcut(shortcut)) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Shortcut removed successfully"))
       |> stream_delete_by_dom_id(:automator_shortcuts, dom_id)}
    else
      error ->
        Logger.error("cannot remove shortcut: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, gettext("Cannot remove the shortcut"))}
    end
  end
end
```

Create `apps/conta_web/lib/conta_web/live/shortcut_live/index.html.heex`:

```heex
<section class="py-6">
  <.breadcrumbs>
    <:breadcrumb label={gettext("Dashboard")} href={~p"/"} />
    <:breadcrumb label={gettext("Shortcuts")} href={~p"/automation/shortcuts"} />
  </.breadcrumbs>

  <div class="card bg-base-100 shadow-xl border border-base-200 mt-6">
    <div class="card-body p-0">
      <div class="p-4 flex justify-between items-center border-b border-base-200">
        <h1 class="text-lg font-semibold">{gettext("Shortcuts")}</h1>
        <.link patch={~p"/automation/shortcuts/new"} class="btn btn-primary">
          <.icon name="hero-plus-circle" class="w-5 h-5 mr-2" />
          <span>{gettext("New Shortcut")}</span>
        </.link>
      </div>
      <div class="overflow-x-auto">
        <.table id="automator_shortcuts" rows={@streams.automator_shortcuts}>
          <:action :let={{_id, shortcut}}>
            <.link
              class="btn btn-ghost btn-sm"
              patch={~p"/automation/shortcuts/#{shortcut}/edit"}
              title={gettext("Edit")}
            >
              <.icon name="hero-pencil" class="w-4 h-4" />
            </.link>
          </:action>
          <:action :let={{id, shortcut}}>
            <.link
              phx-click={JS.push("delete", value: %{id: shortcut.id, dom_id: id})}
              class="btn btn-error btn-outline btn-sm"
              data-confirm={gettext("Are you sure?")}
              title={gettext("Delete")}
            >
              {gettext("Delete")}
            </.link>
          </:action>
          <:col :let={{_id, shortcut}} label={gettext("Name")}>{shortcut.name}</:col>
          <:col :let={{_id, shortcut}} label={gettext("Description")}>{shortcut.description}</:col>
        </.table>
      </div>
    </div>
  </div>
</section>
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/conta_web && mix test test/conta_web/live/shortcut_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/conta_web/lib/conta_web/live/shortcut_live/index.ex apps/conta_web/lib/conta_web/live/shortcut_live/index.html.heex apps/conta_web/test/conta_web/live/shortcut_live_test.exs
git commit -m "Add ShortcutLive.Index (list and delete shortcuts)"
```

---

## Task 10: `ShortcutLive.Form`

**Files:**
- Create: `apps/conta_web/lib/conta_web/live/shortcut_live/form.ex`
- Create: `apps/conta_web/lib/conta_web/live/shortcut_live/form.html.heex`
- Modify: `apps/conta_web/test/conta_web/live/shortcut_live_test.exs`

This mirrors Task 8, minus `type`/`output`, and the test-run result shows the **commands list** the shortcut would dispatch (never actually dispatched).

- [ ] **Step 1: Write the failing tests**

Add to `apps/conta_web/test/conta_web/live/shortcut_live_test.exs`, after `describe "Index"`:

```elixir
  describe "Form" do
    test "creates a new shortcut", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/shortcuts/new")

      assert form_live
             |> form("#shortcut-form", set_shortcut: %{name: ""})
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _index_live, html} =
        form_live
        |> form("#shortcut-form", set_shortcut: %{name: "brand new shortcut"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/automation/shortcuts")

      assert html =~ "Shortcut saved successfully"
      assert html =~ "brand new shortcut"
    end

    test "edits an existing shortcut", %{conn: conn, user: user} do
      shortcut = insert(:shortcut, %{name: "old name"})
      conn = log_in_user(conn, user)

      {:ok, form_live, _html} = live(conn, ~p"/automation/shortcuts/#{shortcut}/edit")

      {:ok, _index_live, html} =
        form_live
        |> form("#shortcut-form", set_shortcut: %{name: "new name"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/automation/shortcuts")

      assert html =~ "Shortcut saved successfully"
      assert html =~ "new name"
    end

    test "test-runs the Lua code and shows the commands without dispatching them", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/shortcuts/new")

      code = ~S[return {status = "ok", commands = {{type = "transaction", data = {foo = "bar"}}}}]

      form_live
      |> form("#shortcut-form", set_shortcut: %{name: "gen commands", code: code})
      |> render_change()

      html = form_live |> element("form[phx-submit=test_run]") |> render_submit()

      assert html =~ "transaction"
      assert html =~ "foo"
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/conta_web && mix test test/conta_web/live/shortcut_live_test.exs`
Expected: FAIL — `ShortcutLive.Form` doesn't exist yet.

- [ ] **Step 3: Implement the LiveView**

Create `apps/conta_web/lib/conta_web/live/shortcut_live/form.ex`:

```elixir
defmodule ContaWeb.ShortcutLive.Form do
  use ContaWeb, :live_view

  import Ecto.Changeset, only: [get_field: 2]
  import Conta.Commanded.Application, only: [dispatch: 1]
  import ContaWeb.AutomatorComponents

  require Logger

  alias Conta.Automator
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

  def handle_event("test_run", %{"test_params" => raw_test_params}, socket) do
    changeset = socket.assigns.form.source
    code = get_field(changeset, :code) || ""
    params_defs = get_field(changeset, :params) || []
    test_params = cast_test_params(params_defs, raw_test_params)

    result = Automator.test_run_shortcut(params_defs, code, test_params)

    {:noreply, assign(socket, :test_result, format_test_result(result))}
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
```

Create `apps/conta_web/lib/conta_web/live/shortcut_live/form.html.heex`:

```heex
<section class="py-6">
  <.breadcrumbs>
    <:breadcrumb label={gettext("Dashboard")} href={~p"/"} />
    <:breadcrumb label={gettext("Shortcuts")} href={~p"/automation/shortcuts"} />
    <:breadcrumb label={@page_title} href="#" />
  </.breadcrumbs>

  <.simple_form for={@form} id="shortcut-form" phx-change="validate" phx-submit="save">
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
      <div class="card bg-base-100 shadow-xl border border-base-200 p-4">
        <h2 class="font-semibold mb-2">{gettext("General data")}</h2>
        <.input field={@form[:name]} type="text" label={gettext("Name")} />
        <.input field={@form[:description]} type="text" label={gettext("Description")} />

        <div class="flex items-center justify-between mt-4 mb-2">
          <h3 class="font-semibold">{gettext("Parameters")}</h3>
          <.button type="button" phx-click="add_param" class="btn-sm">
            {gettext("Add parameter")}
          </.button>
        </div>

        <.inputs_for :let={p} field={@form[:params]}>
          <div class="grid grid-cols-[1fr_1fr_1fr_auto] gap-2 items-end mb-2">
            <.input field={p[:name]} label={gettext("Name")} />
            <.input field={p[:type]} type="select" label={gettext("Type")} options={param_type_options()} />
            <.input field={p[:options]} label={gettext("Options (comma separated)")} />
            <.button type="button" phx-click="del_param" phx-value-index={p.index} class="btn-sm btn-error">
              {gettext("Remove")}
            </.button>
          </div>
        </.inputs_for>
      </div>

      <div class="card bg-base-100 shadow-xl border border-base-200 p-4">
        <.monaco_editor field={@form[:code]} />
      </div>
    </div>

    <:actions>
      <.button class="btn-primary" phx-disable-with={gettext("Saving...")}>
        {gettext("Save")}
      </.button>
      <.link navigate={~p"/automation/shortcuts"} class="btn">{gettext("Cancel")}</.link>
    </:actions>
  </.simple_form>

  <div class="card bg-base-100 shadow-xl border border-base-200 p-4 mt-6">
    <h2 class="font-semibold mb-2">{gettext("Test data")}</h2>
    <p class="text-sm opacity-70 mb-2">
      {gettext("Running here never dispatches real commands — it only shows what would be generated.")}
    </p>
    <form phx-submit="test_run">
      <.test_param_input :for={param <- @params_defs} param={param} />
      <button type="submit" class="btn btn-secondary mt-2">{gettext("Run")}</button>
    </form>

    <div :if={@test_result} class="mt-4">
      <p :if={elem(@test_result, 0) == :error} class="text-error font-semibold">{gettext("Error")}</p>
      <pre class="bg-base-200 p-4 rounded overflow-x-auto text-sm">{elem(@test_result, 1)}</pre>
    </div>
  </div>
</section>
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/conta_web && mix test test/conta_web/live/shortcut_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/conta_web/lib/conta_web/live/shortcut_live/form.ex apps/conta_web/lib/conta_web/live/shortcut_live/form.html.heex apps/conta_web/test/conta_web/live/shortcut_live_test.exs
git commit -m "Add ShortcutLive.Form with Monaco editor and test-run panel"
```

---

## Task 11: Full suite check and manual verification

**Files:** none (verification only)

- [ ] **Step 1: Run the whole test suite**

Run: `mix test`
Expected: PASS, no regressions in any app (`conta`, `conta_web`, `conta_bot`).

- [ ] **Step 2: Run static checks used by this project**

Run: `mix sobelow --config` (as configured for `conta_web`) if part of your usual pre-merge routine, and `mix doctor` if that's part of the project's CI. Confirm no new warnings tied to the files touched in this plan (in particular, the two `# sobelow_skip` GET/POST run routes are untouched and shouldn't trip anything new).

- [ ] **Step 3: Manual browser walkthrough**

With `mix phx.server` running and logged in:
1. Navigate to `/automation/filters`, confirm the empty/listing state renders.
2. Click "New Filter", confirm the Monaco editor loads with Lua syntax highlighting and no console errors besides the expected "could not create web worker" warning (see spec's known limitation).
3. Add a parameter (e.g. `a`, type `integer`), write `return a * 2` in the editor, fill in the test-data field, click "Run", confirm the result panel shows the doubled value.
4. Save, confirm redirect to `/automation/filters` with a success flash and the new filter listed.
5. Edit it, confirm the previously-typed code loads correctly into Monaco.
6. Repeat steps 2-5 for `/automation/shortcuts`, using a shortcut-shaped Lua return (`{status = "ok", commands = {...}}`) and confirming the test panel shows the commands **without** anything appearing in `/ledger/accounts` or `/books/invoices` (i.e., nothing was actually dispatched).
7. Confirm `GET /api/v1/automator/filters` and `GET /api/v1/automator/shortcuts` reflect what was saved through the UI.

- [ ] **Step 4: Final commit (if any cleanup was needed)**

Only if manual verification surfaced small fixes; otherwise this task produces no commit.
