# Design Spec: Plotto Charts Guidelines and Horizontal Legend

## Status: Approved
## Date: 2026-09-13

## Summary
Upgrade financial charts across the application to take advantage of Plotto's native features:
1. **Horizontal Reference Guidelines (`y_guidelines: true`)**:
   Add subtle background reference grid lines along Y-axis tick values to improve data readability across all generated bar and candlestick charts (`chart_patrimony`, `chart_pnl`, `chart_income`, `chart_outcome`, `chart_banks`, `chart_account`).
2. **Horizontal Legend (`legend: :top, legend_orientation: :horizontal`)**:
   In multi-series and multi-category charts (`chart_pnl`, `chart_income`, `chart_outcome`), switch from vertical top-right legends to top horizontal legends. This prevents legend labels from overlapping bars or crowding chart boundaries on smaller screens.
3. **Adaptive CSS Theme Styling (`Conta.Stats.inject_theme_style/2`)**:
   Add styling rules for `line.plotto-guideline` so guidelines render with subtle contrast in both light (`#E5E7EB` with 0.7 opacity) and dark (`#374151` with 0.6 opacity) themes.
4. **Code cleanup**:
   Fix range step warnings `(months - 1)..0//-1` in `Conta.Stats`.

## Scope & Impacted Areas

### 1. `apps/conta/lib/conta/stats.ex`
- `chart_patrimony/1`:
  - Add `y_guidelines: true` to `Plotto.BarChart.new!/2`.
- `chart_pnl/2`:
  - Change `legend: :top_right` to `legend: :top, legend_orientation: :horizontal, y_guidelines: true` in `Plotto.BarChart.new!/2`.
- `chart_by/5` (`chart_income/3` and `chart_outcome/3`):
  - Change `legend: :top_right` to `legend: :top, legend_orientation: :horizontal, y_guidelines: true` in `Plotto.BarChart.new!/2`.
- `chart_banks/2`:
  - Add `y_guidelines: true` to `Plotto.CandlestickChart.new!/2`.
- `chart_account/2`:
  - Add `y_guidelines: true` to `Plotto.CandlestickChart.new!/2`.
- `inject_theme_style/2`:
  - Inject CSS styles targeting `line.plotto-guideline` for `:light`, `:dark`, and `@media (prefers-color-scheme: dark)`:
    - Light: `line.plotto-guideline{stroke:#E5E7EB;stroke-opacity:0.7;}`
    - Dark: `line.plotto-guideline{stroke:#374151;stroke-opacity:0.6;}`
    - System: light defaults + dark media query override.
- Range warning cleanup:
  - Replace `(months - 1)..0` with `(months - 1)..0//-1` in `list_banks/2` and `list_account/2`.

### 2. Tests in `apps/conta/test/conta/stats_test.exs`
- Assert that charts include `opts.y_guidelines == {:dotted, "#E0E0E0"}` (or truthy normalized guideline).
- Assert that multi-series charts (`chart_pnl`, `chart_income`, `chart_outcome`) have `opts.legend_orientation == :horizontal` and `opts.legend == :top`.
- Assert that rendered SVGs contain guideline elements (`<line class="plotto-guideline plotto-guideline-y"`) and that theme styles include `line.plotto-guideline`.

## Verification Plan
- Unit tests in `apps/conta/test/conta/stats_test.exs`.
- Full test suite via `mix test`.
- Static analysis via `mix credo`, `mix format --check-formatted`.
