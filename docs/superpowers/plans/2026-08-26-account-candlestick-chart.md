# Account Candlestick (OHLC) Chart Implementation Plan

## Tasks

- [x] 1. Add `list_account/2`, `chart_account/2`, `graph_account/3` to `Conta.Stats`
  - [x] 1.1 Write unit tests in `apps/conta/test/conta/stats_test.exs` for `list_account/2` with assets and revenue account types (verifying sign handling and OHLC values).
  - [x] 1.2 Implement `list_account/2`, `chart_account/2`, and `graph_account/3` in `apps/conta/lib/conta/stats.ex`.
  - [x] 1.3 Verify `mix test apps/conta/test/conta/stats_test.exs` passes.

- [x] 2. Integrate candlestick chart into `ContaWeb.AccountLive.Show`
  - [x] 2.1 Update `apps/conta_web/lib/conta_web/live/account_live/show.html.heex` to render the candlestick chart with `ChartTooltip` hook and card styling before the account details.
  - [x] 2.2 Add / update LiveView tests in `apps/conta_web/test/conta_web/live/account_live_test.exs` asserting the chart is rendered.
  - [x] 2.3 Verify `mix test apps/conta_web/test/conta_web/live/account_live_test.exs` passes.

- [x] 3. Run full verification with `mix check`
  - [x] 3.1 Run `mix check` (compiler 0 warnings, Credo, Dialyzer, Doctor, Sobelow, tests).
  - [x] 3.2 Commit changes cleanly.


