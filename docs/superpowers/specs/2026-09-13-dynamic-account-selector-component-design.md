# Design Spec: Dynamic Searchable Account Selector Component

## Status: Approved
## Date: 2026-09-13

## Summary
Replace static `<select>` controls for account selection with a dynamic, searchable `LiveComponent` (`ContaWeb.AccountSelectComponent`).
This component addresses two major issues:
1. **DOM and memory bloat**: Previously, every movement row in `ReconciliationLive.Review` (e.g. 50–100 rows) rendered a complete `<select>` with every account in the chart of accounts (hundreds of `<option>` elements per row, totaling 15,000+ DOM nodes). The new component renders only a compact input in its resting state. The dropdown list is rendered strictly on demand and limited to top matching results (max 15 items), and is immediately removed from the DOM and component state when an account is selected or when the dropdown closes.
2. **Substring search by content**: Allows typing to search accounts by any substring of their hierarchy (e.g. searching "bbva" finds `Assets.Banks.BBVA` and `Liabilities.Loan.BBVA`), prioritizing exact matches, segment matches, and containing matches, rather than being limited to native `<select>` prefix jumps.

## Goals & Requirements

### Functional Requirements
- **Idle / Resting State**:
  - Displays currently selected account name (or placeholder e.g. "Select an account").
  - Dropdown options are completely absent from the DOM (`:if={@open && @matches != []}`).
  - `@matches` in socket assigns is empty `[]`.
- **Search & Filter (On Demand)**:
  - Focusing on the input or typing triggers search mode (`@open: true`).
  - Typing filters `@accounts` by case-insensitive substring matching.
  - Smart ranking:
    1. Exact match (`lower == query`)
    2. Starts with query (`String.starts_with?(lower, query)`)
    3. Segment match (`String.contains?(lower, "." <> query)`)
    4. General substring match (`String.contains?(lower, query)`)
  - Results capped at 15 items to avoid large DOM updates.
  - When query is empty, displays first 15 accounts as quick suggestions.
- **Selection & Cleanup**:
  - Clicking an option or pressing Enter selects the account.
  - Notifies the parent LiveView (`send(self(), {:account_selected, id, selected_account})` and/or dispatches form change).
  - Resets `@open: false`, `@matches: []`, and `@query: nil`.
  - Dropdown HTML elements are immediately removed from the DOM.
- **Dismissal**:
  - Clicking outside (`phx-click-away="close"`) or pressing Escape closes the dropdown and resets `@matches: []`, ensuring zero leftover DOM clutter.
- **Integration**:
  - Seamlessly integrates into `ContaWeb.ReconciliationLive.Review` via `<.account_select>` helper or direct `<.live_component>`.
  - Preserves compatibility with existing `#account-form-#{id}` form change handlers and tests.

## Component Architecture (`ContaWeb.AccountSelectComponent`)

### Assigns
- `:id` (required, string): Unique component ID (e.g. `"account-select-#{item_id}"`).
- `:item_id` (optional, string): Domain ID of the row/movement being edited.
- `:value` (optional, string): Currently selected account name (e.g. `"Assets.Banks.Caixa"`).
- `:accounts` (required, list of strings): Full list of available account names.
- `:placeholder` (optional, string): Input placeholder text (default: `gettext("Select an account")`).
- `:class` (optional, string): Extra CSS classes for the outer container.
- Internal assigns:
  - `:open` (boolean): `true` when dropdown is active, `false` otherwise. Default `false`.
  - `:query` (string or nil): Current search text typed by user. Default `nil`.
  - `:matches` (list of strings): Filtered accounts matching query (empty `[]` when `@open == false`).
  - `:active_index` (integer): Index of highlighted option for keyboard navigation (default `0`).

### Events & Lifecycle
- `update(assigns, socket)`:
  - Merges external assigns.
  - Preserves or initializes `@open: false`, `@matches: []`, `@query: nil`, `@active_index: 0`.
- `handle_event("open", _params, socket)`:
  - Sets `@open: true`, `@query: ""`, `@matches: filter_accounts(accounts, "", 15)`, `@active_index: 0`.
- `handle_event("search", %{"query" => query}, socket)`:
  - Filters accounts using `filter_accounts(accounts, query, 15)`.
  - Sets `@open: true`, `@query: query`, `@matches: matches`, `@active_index: 0`.
- `handle_event("select", %{"account" => account}, socket)`:
  - Updates `@value: account`, closes dropdown (`@open: false`, `@matches: []`, `@query: nil`).
  - Notifies parent LiveView via `send(self(), {:account_selected, socket.assigns[:item_id] || socket.assigns.id, account})`.
- `handle_event("close", _params, socket)`:
  - Closes dropdown: `@open: false`, `@matches: []`, `@query: nil`.
- `handle_event("keydown", %{"key" => key}, socket)`:
  - `"ArrowDown"`: increments `@active_index` bounded by `length(@matches) - 1`.
  - `"ArrowUp"`: decrements `@active_index` bounded by `0`.
  - `"Enter"`: selects `Enum.at(@matches, @active_index)`.
  - `"Escape"`: closes dropdown.

## Verification Plan
1. Unit tests in `apps/conta_web/test/conta_web/components/account_select_component_test.exs`:
   - Verify resting state renders only input, no dropdown options in DOM.
   - Verify focus/search renders matching accounts by substring.
   - Verify selecting an account empties `@matches`, removes dropdown from DOM, and notifies parent.
   - Verify click-away / close removes dropdown from DOM.
   - Verify keyboard navigation (Escape, ArrowDown, Enter).
2. Integration tests in `apps/conta_web/test/conta_web/live/reconciliation_live/review_test.exs`:
   - Existing tests passing.
   - New tests verifying selecting account updates movement and cleans DOM.
3. Umbrella tests: `mix test`.
4. Static checks: `mix format --check-formatted` and `mix credo --strict`.
