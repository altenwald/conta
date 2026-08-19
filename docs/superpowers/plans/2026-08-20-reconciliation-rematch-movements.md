# Implementation Plan: Re-evaluate Match Rules on Reconciliation Movements

## Goal
Allow users to re-evaluate match rules against selected or individual movements in the Reconciliation Review screen (`/reconciliation/review`).

## Tasks

- [x] **Task 1: Domain Command & Aggregate Handler for `RematchMovements`**
  - Create `apps/conta/lib/conta/command/rematch_movements.ex`.
  - In `apps/conta/lib/conta/commanded/router.ex`, route `RematchMovements` to `Reconciliation`.
  - In `apps/conta/lib/conta/aggregate/reconciliation.ex`, implement `execute(%RematchMovements{})` re-evaluating rules with `evaluate_rules/2` and generating `MovementUpdated` events for changed items.
  - In `apps/conta/lib/conta/reconciliation.ex`, add `rematch_movements/1` and `rematch_movement/1`.
  - Add unit tests in `apps/conta/test/aggregate/reconciliation_test.exs` and `apps/conta/test/conta/reconciliation_context_test.exs`.

- [x] **Task 2: LiveView Event Handlers in `ContaWeb.ReconciliationLive.Review`**
  - In `apps/conta_web/lib/conta_web/live/reconciliation_live/review.ex`:
    - Add `handle_event("rematch", %{"id" => id}, socket)`.
    - Add `handle_event("rematch_selected", %{"ids" => ids_param}, socket)`.
    - Refresh `@movements` and update `@selected` and flash messages.

- [x] **Task 3: Update `review.html.heex` Template**
  - In `apps/conta_web/lib/conta_web/live/reconciliation_live/review.html.heex`:
    - Add "Re-evaluate rules" button in `movements-without-account` toolbar (`selected_bottom`).
    - Add single-row rematch button (`hero-arrow-path`) next to delete button in `movements-without-account` row actions.

- [x] **Task 4: Add Tests in `review_test.exs` & Run Full Verifications**
  - In `apps/conta_web/test/conta_web/live/reconciliation_live/review_test.exs`:
    - Test individual rematch row button.
    - Test batch rematch toolbar button.
  - Run `mix format`, `mix compile --warnings-as-errors`, and full `mix test`.
