# Implementation Plan: Telegram Bot Candle Chart Command (Task #19)

- [x] **Task 1: Extend `Conta.Stats.list_account/2` to accept account names (string and list)**
  - [x] Add tests in `apps/conta/test/conta/stats_test.exs` verifying `list_account` and `chart_account` with dotted binary names and list names.
  - [x] Implement clauses in `apps/conta/lib/conta/stats.ex` for `is_list(account_name)` and `is_binary(account)` when containing dots or resolved via `Conta.Ledger.get_account_by_name/1`.
  - [x] Run `mix test apps/conta/test/conta/stats_test.exs` to verify.

- [x] **Task 2: Register `/candle` command in `ContaBot.Action`**
  - [x] Add `command("candle", description: "Get candle chart for an account")` in `apps/conta_bot/lib/conta_bot/action.ex`.
  - [x] Verify compilation and routing to `ContaBot.Action.Candle`.

- [x] **Task 3: Implement `ContaBot.Action.Candle`**
  - [x] Create `apps/conta_bot/lib/conta_bot/action/candle.ex`.
  - [x] Implement:
    - Direct command with arguments (`/candle <account> [months]`).
    - Interactive `/candle` account selector (`choose_account/5`).
    - Hierarchy drilldown (`{:callback, account}`).
    - Event selection asking for period (`{:event, account}` with 3, 6, 12, 24 months options).
    - Callback for month choice (`{:callback, "months " <> data}`).
    - Photo dispatch via `@bot_api.send_photo/3` and callback message cleanup.
    - Error handling for nonexistent accounts and invalid months.

- [x] **Task 4: Add comprehensive tests in `ContaBot.Action.CandleTest`**
  - [x] Create `apps/conta_bot/test/conta_bot/action/candle_test.exs`.
  - [x] Add tests for:
    - `/candle` initial command presenting categories.
    - `/candle <account>` direct execution sending photo.
    - `/candle <account> 6` direct execution with custom months.
    - Drilldown callback querying subaccounts.
    - Event selection prompting for month options.
    - Month selection callback generating chart and sending photo.
    - Unknown account error handling.

- [x] **Task 5: Verification and Task Completion**
  - [x] Run `mix test`.
  - [x] Run `mix check` (compiler warnings, Credo, Dialyzer, etc.).
  - [x] Commit changes cleanly (no AI attribution, NO git push).
  - [x] Mark Task #19 as completed in Backlog.
