# Propagate :consistency in Conta.Projector Implementation Plan

- **Spec**: `docs/superpowers/specs/2026-09-13-propagate-projector-consistency-design.md`
- **Date**: 2026-09-13
- **Ticket**: #1 [M] [T1]

---

## Tasks

- [x] **Task 1: Add tests verifying `:consistency` propagation in `Conta.Projector` and synchronous dispatch with `consistency: :strong`**
  - [x] Write a test in `apps/conta/test/projector_test.exs` verifying that a module using `Conta.Projector` with `consistency: :strong` registers its handler options with `consistency: :strong`.
  - [x] Write an integration test demonstrating that `dispatch(command, consistency: :strong)` blocks until the projector has written to PostgreSQL.
  - [x] Run test to verify failure before the fix.

- [x] **Task 2: Fix `Conta.Projector` to pass through `:consistency` to `Commanded.Event.Handler`**
  - [x] In `apps/conta/lib/conta/projector.ex`, modify `@handler_opts` from `Keyword.drop(@opts, [:repo, :timeout, :consistency])` to `Keyword.drop(@opts, [:repo, :timeout])`.
  - [x] Verify that Task 1 tests now pass.

- [x] **Task 3: Review projector consistency configuration and context dispatch helpers**
  - [x] Update all 6 projectors (`Book`, `Directory`, `Stats`, `Reconciliation`, `Ledger`, `Automator`) to use `Application.compile_env(:conta, [__MODULE__, :consistency], Application.compile_env(:conta, :consistency, :strong))`.
  - [x] In `config/config.exs`, configure `config :conta, consistency: :strong` so production projectors are registered as strong (allowing callers to opt-in to strong consistency on dispatch).
  - [x] In `apps/conta/lib/conta/reconciliation.ex`, allow `dispatch/2` and `update_movement/3` with options (`opts \\ []`) so callers can request `consistency: :strong`.
  - [x] Update `reconciliation_context_test.exs` to verify that `update_movement` with `consistency: :strong` allows immediate read without `eventually/1,2`.

- [x] **Task 4: Verification and Clean Check**
  - [x] Run full test suite (`mix test`) from repository root.
  - [x] Run `mix check` (warnings-as-errors, formatting, Credo, Dialyzer, Doctor, Sobelow).
  - [x] Update plan checkboxes.
  - [x] Mark task #1 as completed in Backlog with commit hash and resolution.
