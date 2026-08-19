# Design Spec: Batch Selection and Deletion Controls for Movements Without Account

## Context & Motivation
On the bank reconciliation review page (`/ledger/reconciliation`), imported movements are grouped into two sections:
1. **Movements with an account**: Entries that matched a rule or had an account manually assigned. This table has row checkboxes and a toolbar for selecting all, deselecting all, inverting selection, confirming, and batch deleting.
2. **Movements without an account**: Entries that had no matching rule and need manual assignment or deletion. Currently, this table lacks checkboxes and toolbar controls, requiring users to manually click "Delete" on each row individually. When importing bank statements with many non-transactional or ignorable rows, deleting them one by one is tedious and inconvenient.

## Requirements
1. Add row checkboxes to each row in "Movements without an account".
2. Add a toolbar to the card header of "Movements without an account" with:
   - `{gettext("%{count} selected", count: count)}` badge/label.
   - Join button group:
     - `Select all` (`phx-click="select_all"` with scope `without_account`).
     - `Deselect all` (`phx-click="deselect_all"` with scope `without_account`).
     - `Invert selection` (`phx-click="invert_selection"` with scope `without_account`).
   - `Delete` button (`phx-click="remove_selected"` passing selected unassigned IDs) with `data-confirm={gettext("Are you sure?")}`.
3. Update `ContaWeb.ReconciliationLive.Review` to support scoped selection actions (`scope: "with_account"` vs `scope: "without_account"`, defaulting to all selectable when no scope is provided for backwards compatibility).
4. Maintain strict TDD with comprehensive tests in `review_test.exs`.

## Architecture & Implementation Details

### View & Template (`review.html.heex`)
- Split `@movements` into `{top, bottom}`.
- Compute:
  - `selected_top = MapSet.filter(@selected, fn id -> Enum.any?(top, &(&1.id == id and not &1.transacted)) end)`
  - `selected_bottom = MapSet.filter(@selected, fn id -> Enum.any?(bottom, &(&1.id == id)) end)`
- In top card header:
  - `Select all` with `phx-value-scope="with_account"`.
  - `Deselect all` with `phx-value-scope="with_account"`.
  - `Invert selection` with `phx-value-scope="with_account"`.
  - `Confirm` with `phx-value-ids={Enum.join(selected_top, ",")}`.
  - `Delete` with `phx-value-ids={Enum.join(selected_top, ",")}`.
- In bottom card header:
  - Add toolbar with count of `selected_bottom`.
  - `Select all` with `phx-value-scope="without_account"`.
  - `Deselect all` with `phx-value-scope="without_account"`.
  - `Invert selection` with `phx-value-scope="without_account"`.
  - `Delete` (`btn-error`) with `phx-value-ids={Enum.join(selected_bottom, ",")}`, disabled when `Enum.empty?(selected_bottom)`, with `data-confirm={gettext("Are you sure?")}`.
- In bottom table:
  - Add checkbox column header `<th class="w-0"></th>`.
  - Add row checkbox:
    ```heex
    <td>
      <input
        type="checkbox"
        class="checkbox checkbox-sm"
        checked={MapSet.member?(@selected, movement.id)}
        phx-click="toggle_select"
        phx-value-id={movement.id}
      />
    </td>
    ```

### LiveView (`review.ex`)
- Update `handle_event("select_all", params, socket)`:
  - `scope == "without_account"`: select all in `bottom`.
  - `scope == "with_account"`: select all in `top` (non-transacted).
  - default / no scope: select all selectable movements across both.
- Update `handle_event("deselect_all", params, socket)`:
  - `scope == "without_account"`: remove `bottom` IDs from `selected`.
  - `scope == "with_account"`: remove `top` IDs from `selected`.
  - default / no scope: empty `selected`.
- Update `handle_event("invert_selection", params, socket)`:
  - `scope == "without_account"`: invert within `bottom`.
  - `scope == "with_account"`: invert within `top`.
  - default / no scope: invert within all selectable.

## Testing Plan
- Test bottom table displays checkboxes.
- Test "Select all" in bottom table selects only bottom table movements.
- Test "Deselect all" in bottom table deselects only bottom table movements.
- Test "Invert selection" in bottom table inverts only bottom table movements.
- Test "Delete" in bottom table deletes selected unassigned movements in batch.
