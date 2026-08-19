# Implementation Plan: Batch Selection & Deletion Controls for Movements Without Account

## Goal
Enable multi-selection and batch deletion for entries in the "Movements without an account" section of the bank reconciliation review page (`/ledger/reconciliation`).

## Tasks

- [x] **Task 1: Add Failing Unit & LiveView Tests for Unassigned Movements Selection and Batch Deletion**
  - Update `apps/conta_web/test/conta_web/live/reconciliation_live/review_test.exs`:
    - Verify checkboxes exist for rows without accounts.
    - Verify "Select all", "Deselect all", and "Invert selection" scoped to `without_account`.
    - Verify batch "Delete" button removes all selected movements without accounts.
    - Run tests to confirm failures before implementation.

- [x] **Task 2: Implement Scoped Selection in `review.ex`**
  - In `apps/conta_web/lib/conta_web/live/reconciliation_live/review.ex`:
    - Update `selectable_ids` or add `selectable_ids(movements, scope)` to return unassigned IDs when `scope == "without_account"`, assigned non-transacted IDs when `scope == "with_account"`, and all when `scope == nil`.
    - Update `select_all`, `deselect_all`, and `invert_selection` to support `scope` params.

- [x] **Task 3: Update Template `review.html.heex` with Toolbar and Checkboxes in Bottom Table**
  - In `apps/conta_web/lib/conta_web/live/reconciliation_live/review.html.heex`:
    - Add toolbar in the header of the "Movements without an account" card:
      - Selected count badge.
      - "Select all" button (`phx-click="select_all" phx-value-scope="without_account"`).
      - "Deselect all" button (`phx-click="deselect_all" phx-value-scope="without_account"`).
      - "Invert selection" button (`phx-click="invert_selection" phx-value-scope="without_account"`).
      - "Delete" button (`phx-click="remove_selected" phx-value-ids={Enum.join(selected_bottom, ",")}` disabled={Enum.empty?(selected_bottom)} `data-confirm={gettext("Are you sure?")}`).
    - Add checkbox column header and checkbox input to each row in the bottom table.
    - Update top table toolbar buttons with `phx-value-scope="with_account"`.

- [x] **Task 4: Run Verification & Quality Checks**
  - Run `mix test apps/conta_web/test/conta_web/live/reconciliation_live/review_test.exs`.
  - Run `mix test` and `mix check` from umbrella root.
