# Design Spec: Re-evaluate Match Rules on Reconciliation Movements

## Overview
When users adjust or add reconciliation match rules (at `/reconciliation/matches`), they need a way to re-evaluate those rules against pending bank statement movements (at `/reconciliation/review`) without having to delete and re-import the file.

This feature adds:
1. **Batch Re-evaluation Button** in the selection toolbar of both "Movements without an account" and "Movements with an account" tables.
2. **Individual Re-evaluation Button** (`hero-arrow-path` icon button) in each row's action column.

## Architecture & Flow (CQRS/ES)

### 1. Command
- `Conta.Command.RematchMovements`:
  - `ids`: list of binary IDs (UUIDs).
  - `reconciliation`: string stream ID (defaults to `"default"`).

### 2. Aggregate (`Conta.Aggregate.Reconciliation`)
- Handled via `execute(%Reconciliation{movements: movements, match_rules: match_rules}, %RematchMovements{ids: ids})`.
- For each movement in `ids`:
  - Skip if non-existent or `transacted == true`.
  - Calculate `{account_name, description} = evaluate_rules(match_rules, movement)`.
  - If `{account_name, description}` changed compared to current movement state:
    - Generate `MovementUpdated.changeset(%{id: id, on_date: movement.on_date, description: description, amount: movement.amount, currency: movement.currency, account_name: account_name})`.
- Commanded dispatches the resulting `MovementUpdated` events.

### 3. Context (`Conta.Reconciliation`)
- `rematch_movements(ids)`: Dispatches `%RematchMovements{ids: ids}`.
- `rematch_movement(id)`: Dispatches `%RematchMovements{ids: [id]}`.

### 4. LiveView (`ContaWeb.ReconciliationLive.Review`)
- Event `handle_event("rematch", %{"id" => id}, socket)`:
  - Calls `Reconciliation.rematch_movement(id)`.
  - Refreshes `@movements` from database projection.
  - Adds flash message.
- Event `handle_event("rematch_selected", %{"ids" => ids_param}, socket)`:
  - Splits IDs, calls `Reconciliation.rematch_movements(ids)`.
  - Refreshes `@movements`.
  - Clears or updates `@selected`.
  - Adds flash message with updated count.

### 5. UI Templates (`review.html.heex`)
- Add "Re-evaluate rules" button (`btn btn-secondary` with `hero-arrow-path` icon) to both toolbar sections when items are selected.
- Add icon button `btn btn-ghost btn-sm btn-circle` with `hero-arrow-path` next to delete button on each row.
