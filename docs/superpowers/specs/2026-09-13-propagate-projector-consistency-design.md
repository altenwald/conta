# Propagate :consistency in Conta.Projector Design

- **Date**: 2026-09-13
- **Author**: Antigravity & Manuel
- **Status**: Approved
- **Ticket**: #1 [M] [T1]

---

## 1. Problem Statement

In `Conta.Projector` (`apps/conta/lib/conta/projector.ex:25`), options passed to the projector macro are filtered before being forwarded to `Commanded.Event.Handler`:

```elixir
@handler_opts Keyword.drop(@opts, [:repo, :timeout, :consistency])
```

By dropping `:consistency`, Commanded never receives the consistency configuration for any projector in the entire application. As a result:
1. Every projector (`Conta.Projector.Book`, `Conta.Projector.Directory`, `Conta.Projector.Stats`, `Conta.Projector.Reconciliation`, `Conta.Projector.Ledger`, `Conta.Projector.Automator`) always registers as `:eventual`, regardless of whether a module specifies `consistency: Application.compile_env(:conta, :consistency, :eventual)` or whether `config :conta, consistency: :strong` is set in configuration.
2. When callers dispatch commands requesting `dispatch(command, consistency: :strong)` or `consistency: [ProjectorModule]`, Commanded's `Commanded.Middleware.ConsistencyGuarantee` does not wait for the projectors to finish writing to PostgreSQL because Commanded explicitly requires handlers to be registered as `:strong` in order to wait for them.
3. This creates latent race conditions for any read-after-write operations across production and testing environments, forcing tests to resort to ad-hoc polling (`eventually/1,2`).

---

## 2. Goals & Requirements

1. **Pass `:consistency` to `Commanded.Event.Handler`**:
   Update `Conta.Projector` (`apps/conta/lib/conta/projector.ex`) to preserve `:consistency` in `@handler_opts` by only dropping `[:repo, :timeout]`.
2. **Review & Configure Projector Consistency**:
   - Ensure all projectors can specify `:consistency` via their options, defaulting to `Application.compile_env(:conta, [__MODULE__, :consistency], Application.compile_env(:conta, :consistency, :strong))` or `:eventual`.
   - In `config/config.exs`, set default consistency to `:strong` (or configure per-projector) so that dispatching commands with `consistency: :strong` works consistently across environments. Note that default command dispatch without options (`dispatch(command)`) remains asynchronous (`:eventual`) and is not blocked unless the caller explicitly passes `consistency: :strong`.
3. **Allow `dispatch/2` in Contexts**:
   Ensure context modules such as `Conta.Reconciliation` import or expose `dispatch/2` (allowing `opts` like `consistency: :strong`) so callers can wait for projections when needed.
4. **Unit and Integration Verification**:
   - Add a unit test verifying that `Conta.Projector` preserves `:consistency` in the generated event handler options.
   - Verify with a test that dispatching with `consistency: :strong` waits for the projector to write to PostgreSQL before returning, eliminating the need for polling in read-after-write scenarios.
   - Ensure all existing unit and integration tests pass without regression.

---

## 3. Detailed Architecture & Changes

### 3.1. `Conta.Projector` (`apps/conta/lib/conta/projector.ex`)

Change line 25 from:
```elixir
@handler_opts Keyword.drop(@opts, [:repo, :timeout, :consistency])
```
to:
```elixir
@handler_opts Keyword.drop(@opts, [:repo, :timeout])
```

When a projector module passes `consistency: ...` in `use Conta.Projector, ...`, it will now be passed directly to `use Commanded.Event.Handler, @handler_opts`.

### 3.2. Projectors Consistency Configuration

All 6 domain projectors:
- `Conta.Projector.Book`
- `Conta.Projector.Directory`
- `Conta.Projector.Stats`
- `Conta.Projector.Reconciliation`
- `Conta.Projector.Ledger`
- `Conta.Projector.Automator`

Currently specify:
```elixir
consistency: Application.compile_env(:conta, :consistency, :eventual)
```

Enhance the lookup to support per-projector configuration if desired:
```elixir
consistency:
  Application.compile_env(
    :conta,
    [__MODULE__, :consistency],
    Application.compile_env(:conta, :consistency, :strong)
  )
```

In `config/config.exs`, set `config :conta, consistency: :strong` (already set in `config/test.exs`).
Because Commanded only waits for `:strong` handlers when a dispatch explicitly requests `consistency: :strong`, setting handlers to `:strong` gives callers full control over whether to await projections or fire-and-forget.

### 3.3. Context Modules (`Conta.Reconciliation`, etc.)

Update `import Conta.Commanded.Application, only: [dispatch: 1]` to:
```elixir
import Conta.Commanded.Application, only: [dispatch: 1, dispatch: 2]
```
and allow `update_movement/3` (with default `opts \\ []`) so callers can pass `consistency: :strong` when chaining operations.

---

## 4. Verification Plan

1. **Unit Test**: Test that `Conta.Projector` passes `:consistency` to Commanded event handler.
2. **Integration Test**: Dispatch with `consistency: :strong` and assert read model is updated synchronously upon dispatch return.
3. **Full Suite**: Run `mix test` and `mix check` from repository root.
