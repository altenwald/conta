# Design Spec: Replace Contex and Resvg with Plotto

## Status: Draft
## Date: 2026-08-20

## Summary
Migrate the chart generation across Conta (`apps/conta`, `apps/conta_web`, `apps/conta_bot`) from `contex` (GitHub fork) and `resvg` (Rustler NIF) to `plotto` (`~> 0.1.0`).

## Goals
- Remove `contex` and `resvg` dependencies from `apps/conta/mix.exs` and `mix.lock`.
- Add `{:plotto, "~> 0.1.0"}` dependency to `apps/conta/mix.exs`.
- Update `Conta.Stats`:
  - `graph_patrimony/1`: Produce `Plotto.BarChart` struct, returning SVG string or chart struct.
  - `graph_pnl/2`: Produce `Plotto.BarChart` in `:grouped` mode with negative/mixed value support.
  - `graph_income/3` & `graph_outcome/3`: Produce `Plotto.BarChart` in `:stacked` mode with top accounts + "Others".
  - Optionally provide `png_*` or helper functions in `Conta.Stats` or allow callers to render PNG with `Plotto.to_png/1`.
- Update `ContaWeb.DashboardController`:
  - Render PNG responses via `Plotto.to_png!/1` instead of `Resvg.svg_string_to_png_buffer/2`.
- Update `ContaBot.Action.Graph`:
  - Generate PNG binaries for Telegram photos via `Plotto.to_png!/1` directly in memory without `/tmp`.
- Ensure all tests in `apps/conta`, `apps/conta_web`, and `apps/conta_bot` pass with `mix test` and `mix check`.

## Architecture & Implementation

### 1. Dependency Changes
In `apps/conta/mix.exs`:
- Remove `{:contex, "~> 0.5", github: "manuel-rubio/contex"}`
- Remove `{:resvg, "~> 0.3"}`
- Add `{:plotto, "~> 0.1.0"}`

### 2. `Conta.Stats` Chart Implementation
- `chart_patrimony(currency)`:
  - Data: `[%{name: "Patrimony", data: [%{label: to_date(p), value: to_float(p.balance)}]}]`
  - Chart: `Plotto.BarChart.new!(series, width: 640, height: 480)`
  - `graph_patrimony(currency)`: `chart_patrimony(currency) |> Plotto.to_svg!()`
- `chart_pnl(currency, months)`:
  - Series:
    - `"Profits"` -> `[%{label: date, value: profits}]`
    - `"Losses"` -> `[%{label: date, value: loses}]` (or negative value if applicable)
    - `"Balance"` -> `[%{label: date, value: balance}]`
  - Chart: `Plotto.BarChart.new!(series_list, mode: :grouped, legend: :top_right, width: 640, height: 480)`
  - `graph_pnl(currency, months)`: `chart_pnl(currency, months) |> Plotto.to_svg!()`
- `chart_by(table, data, currency, groups, months)` (for income & outcome):
  - Categories: all distinct dates ordered chronologically.
  - Accounts (headers): `top_accounts(table, groups, months) ++ ["Others"]`
  - For each account name, build a series:
    `%{name: account_name, data: Enum.map(dates, fn date -> %{label: date, value: Map.get(lookup[date], account_name, 0.0)} end)}`
  - Chart: `Plotto.BarChart.new!(series_list, mode: :stacked, legend: :top_right, width: 640, height: 480)`
  - `graph_income/3` / `graph_outcome/3`: calls `chart_by(...) |> Plotto.to_svg!()`

### 3. Controller & Bot Integration
- `ContaWeb.DashboardController`:
  - `to_png(svg)` or direct `Plotto.to_png/1` call.
- `ContaBot.Action.Graph`:
  - Uses `Plotto.to_png!/1` or `Conta.Stats` chart generation.
