# Specification: Batch Inline Edits in Reconciliation Review

## 1. Overview & Problem Statement

In the bank reconciliation review screen (`ContaWeb.ReconciliationLive.Review`), movement rows display editable fields for:
- `on_date` (Date)
- `description` (Text)
- `amount` (Decimal currency)

Currently, each editable input is wrapped in `<form phx-change="update_field">`. On every keystroke, the LiveView triggers `handle_event("update_field", ...)`, which immediately invokes `Reconciliation.update_movement(id, changes)`.

### Problem
1. **EventStore saturation**: Typing a single description like "Suscripción mensual" emits 19 `MovementUpdated` events to EventStore.
2. **Command & Projection overhead**: Following Task #1, projectors can run with `:strong` consistency, which forces each keystroke dispatch to synchronize across Postgres read models before returning. This creates noticeable UI lag and unnecessary database churn.
3. **Accidental writes**: Incomplete or intermediate states (e.g. typing a partial negative number `"-"` or partial date) are dispatched as real business commands.

### Solution
Buffer inline edits in the LiveView socket state (`:pending_changes`). A row with unsaved changes is visually marked as modified and its actions column displays explicit **Save** and **Cancel** buttons (replacing the standard Delete / Rematch buttons). Clicking Save dispatches a single `UpdateMovement` command with all accumulated changes for that row. Clicking Cancel restores original values from memory without touching the backend.

---

## 2. Technical Design

### 2.1 State Representation

The LiveView assigns will include:
```elixir
assign(socket, :pending_changes, %{})
```
Where `:pending_changes` is a map keyed by movement `id`:
```elixir
%{
  "movement-uuid" => %{
    "description" => "New description",
    "amount" => "45.00",
    "on_date" => "2026-09-13"
  }
}
```

### 2.2 Event Handling

#### 2.2.1 `update_field` (Input keystroke/change)
- Triggered by `phx-change="update_field"` on `<.editable>` forms.
- Params: `%{"id" => id, "field" => field, "value" => value}`.
- Allowed fields: `@editable_fields` (`on_date`, `description`, `amount`).
- Logic:
  - Find the movement in `@movements`.
  - Compare `value` against the movement's persisted value:
    - `description`: `movement.description || ""`
    - `on_date`: `Date.to_iso8601(movement.on_date)`
    - `amount`: compare parsed cents or formatted string with `movement.amount`.
  - If `value` matches the persisted value:
    - Remove `field` from `pending_changes[id]`.
    - If `pending_changes[id]` is now empty, remove `id` from `pending_changes`.
  - If `value` differs:
    - Put `field => value` into `pending_changes[id]`.
  - **No Commanded dispatch or database query occurs.**

#### 2.2.2 `save_row` (Confirm changes)
- Triggered by clicking the Save button or submitting any form within the row via Enter key (`phx-submit="save_row"`).
- Params: `%{"id" => id}`.
- Logic:
  - Retrieve `changes = Map.get(socket.assigns.pending_changes, id)`.
  - If `nil` or empty, do nothing (`{:noreply, socket}`).
  - Transform and validate changes for `Reconciliation.update_movement/2`:
    - `"amount"`: parse using `parse_amount/1` to integer cents.
    - `"on_date"`: string date (parsed/validated by changeset).
    - `"description"`: trimmed string.
  - Dispatch `Reconciliation.update_movement(id, parsed_changes)`.
  - On `:ok`:
    - Update movement in `socket.assigns.movements` using existing `cast_movement/2`.
    - Remove `id` from `socket.assigns.pending_changes`.
    - Remove `id` from `socket.assigns.errors`.
  - On `{:error, reason}`:
    - Put `reason` into `socket.assigns.errors[id]`.
    - Keep row in pending state so the user can fix or cancel.

#### 2.2.3 `cancel_row` (Discard changes)
- Triggered by clicking the Cancel button (`phx-click="cancel_row"`).
- Params: `%{"id" => id}`.
- Logic:
  - Remove `id` from `socket.assigns.pending_changes`.
  - Remove `id` from `socket.assigns.errors`.
  - Row fields automatically re-render with persisted values from `movement`.

#### 2.2.4 Cleanup on other actions
- When a movement is removed via `remove` or `remove_selected`:
  - Drop `id` / `ids` from `pending_changes`.

---

## 3. UI/UX Design

### 3.1 Row Highlighting
When a row has pending changes (`Map.has_key?(@pending_changes, movement.id)`):
- Row styling: Add `bg-info/10 border-l-4 border-info` (or similar daisyUI styling) so the user immediately sees which row is being modified.
- Field values: `<.editable>` displays the buffered value from `pending_changes[movement.id][field]` if present, otherwise the original movement value.

### 3.2 Action Buttons
In the actions column (`<td>` at the end of the row):
- **Normal state (unmodified)**:
  - Movements with account: `Delete` (or `Retry cleanup`).
  - Movements without account: `Rematch` icon button + `Delete`.
- **Modified state (has pending changes)**:
  - Replace normal buttons with a button group:
    - **Save button**: `<button type="button" phx-click="save_row" phx-value-id={movement.id} class="btn btn-success btn-sm">` with `hero-check` icon and "Save" label.
    - **Cancel button**: `<button type="button" phx-click="cancel_row" phx-value-id={movement.id} class="btn btn-ghost btn-sm">` with `hero-x-mark` icon and "Cancel" label.

### 3.3 Keyboard Ergonomics
- In `<.editable>`: `<form phx-change="update_field" phx-submit="save_row" ...>`
- Pressing `Enter` while inside any editable input saves the row immediately.

---

## 4. Verification & Testing

1. **Unit/Integration LiveView Tests**:
   - `render_change` updates the pending assign and input value without calling `update_movement` or modifying the database.
   - Row renders Save and Cancel buttons while modified; Delete button is hidden.
   - Clicking Save calls `update_movement`, commits to the database, removes pending state, and restores normal buttons.
   - Clicking Cancel reverts the input value to the database value without any database write.
   - Submitting the form (Enter key) triggers Save.
   - Editing multiple fields (`description` and `amount`) on the same row buffers both and saves them in a single command.
2. **Regression Verification**:
   - Run `mix test apps/conta_web/test/conta_web/live/reconciliation_live/review_test.exs`.
   - Run `mix check`.
