# Implementation Plan: Dashboard Banks Candlestick Chart and SVG Web Delivery

## Tasks

- [x] 1. Implement bank account candle data extraction and chart generation in `Conta.Stats`
  - [x] 1.1 Write tests in `apps/conta/test/conta/stats_test.exs` for `list_banks/2`, `chart_banks/2`, and `graph_banks/2`
  - [x] 1.2 Implement `list_banks/2`, `chart_banks/2`, and `graph_banks/2` in `apps/conta/lib/conta/stats.ex`
  - [x] 1.3 Verify tests pass with `mix test apps/conta/test/conta/stats_test.exs`

- [x] 2. Update `ContaWeb.DashboardController` to deliver SVG format and support `banks`
  - [x] 2.1 Write controller tests in `apps/conta_web/test/conta_web/controllers/dashboard_controller_test.exs` asserting `image/svg+xml` responses for all chart types including `banks`
  - [x] 2.2 Update `apps/conta_web/lib/conta_web/controllers/dashboard_controller.ex` to render SVG via `Plotto.to_svg!/1` with content-type `image/svg+xml`
  - [x] 2.3 Verify controller tests pass with `mix test apps/conta_web/test/conta_web/controllers/dashboard_controller_test.exs`

- [x] 3. Update `ContaWeb.DashboardLive` template with responsive double-width Banks chart card
  - [x] 3.1 Update `apps/conta_web/lib/conta_web/live/dashboard_live/index.html.heex` to add the Banks chart in a `col-span-12` card
  - [x] 3.2 Add LiveView test in `apps/conta_web/test/conta_web/live/dashboard_live_test.exs`
  - [x] 3.3 Verify LiveView tests pass with `mix test apps/conta_web/test/conta_web/live/`

- [x] 4. Update `ContaBot.Action.Graph` to include Banks option (delivering PNG via Telegram)
  - [x] 4.1 Update `apps/conta_bot/lib/conta_bot/action/graph.ex` to add `Banks` choice and handler
  - [x] 4.2 Add test in `apps/conta_bot/test/conta_bot/action/graph_test.exs`
  - [x] 4.3 Verify bot tests pass with `mix test apps/conta_bot/`

- [x] 5. Run full verification with `mix test` and `mix check`
  - [x] 5.1 Run `mix test` across all apps
  - [x] 5.2 Run `mix check` and fix any warnings or issues
