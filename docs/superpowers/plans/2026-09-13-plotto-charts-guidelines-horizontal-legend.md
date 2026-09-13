# Plan: Plotto Charts Guidelines and Horizontal Legend

- [x] Task 1: Write tests for guidelines, horizontal legend, and guideline theme styling <!-- id: 0 -->
  - [x] Add tests in `apps/conta/test/conta/stats_test.exs` asserting `y_guidelines` on `chart_patrimony`, `chart_pnl`, `chart_outcome`, `chart_income`, `chart_banks`, `chart_account`
  - [x] Add tests asserting `legend: :top` and `legend_orientation: :horizontal` on `chart_pnl`, `chart_outcome`, `chart_income`
  - [x] Add tests asserting `line.plotto-guideline` CSS in `inject_theme_style/2`
- [x] Task 2: Implement guidelines, horizontal legend, and styling in `Conta.Stats` <!-- id: 1 -->
  - [x] Update `chart_patrimony/1` with `y_guidelines: true`
  - [x] Update `chart_pnl/2` with `legend: :top, legend_orientation: :horizontal, y_guidelines: true`
  - [x] Update `chart_by/5` with `legend: :top, legend_orientation: :horizontal, y_guidelines: true`
  - [x] Update `chart_banks/2` with `y_guidelines: true`
  - [x] Update `chart_account/2` with `y_guidelines: true`
  - [x] Update `inject_theme_style/2` to inject `line.plotto-guideline` CSS
  - [x] Clean up range warnings `(months - 1)..0//-1` in `list_banks/2` and `list_account/2`
- [x] Task 3: Verification & Backlog Completion <!-- id: 2 -->
  - [x] Run unit tests (`mix test apps/conta/test/conta/stats_test.exs`)
  - [x] Run umbrella test suite (`mix test`)
  - [x] Run formatting check and Credo (`mix format --check-formatted`, `mix credo`)
  - [x] Commit changes with clean commit message (no AI co-author attribution)
  - [x] Complete Task #18 in Backlog and update project spec
