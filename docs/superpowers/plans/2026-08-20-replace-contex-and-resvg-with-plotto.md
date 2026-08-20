# Implementation Plan: Replace Contex and Resvg with Plotto

## Goal
Replace `contex` and `resvg` dependencies with `plotto` (`~> 0.1.0`) across the entire Conta umbrella repo.

## Tasks

- [x] **Task 1: Update dependencies in `apps/conta/mix.exs`**
  - Remove `:contex` and `:resvg`.
  - Add `{:plotto, "~> 0.1.0"}`.
  - Run `mix deps.get` and `mix deps.unlock --unused`.
  - Verify dependencies compile cleanly and commit.

- [x] **Task 2: Migrate `Conta.Stats` to `Plotto`**
  - Refactor `graph_patrimony/1`, `graph_pnl/2`, and `graph_by/5` (`graph_income/3`, `graph_outcome/3`) in `apps/conta/lib/conta/stats.ex`.
  - Also provide helper functions to produce charts or direct PNGs if needed.
  - Add/update tests in `apps/conta/test/` to verify SVG outputs.
  - Verify tests pass and commit.

- [x] **Task 3: Update `ContaWeb.DashboardController` and `ContaBot.Action.Graph`**
  - Update `apps/conta_web/lib/conta_web/controllers/dashboard_controller.ex` to use `Plotto.to_png!/1` or `Conta.Stats`.
  - Update `apps/conta_bot/lib/conta_bot/action/graph.ex` to use `Plotto.to_png!/1` instead of `Resvg`.
  - Verify tests pass and commit.

- [x] **Task 4: Run full verification suite (`mix test`, `mix check`)**
  - Run `mix format --check-formatted`.
  - Run `mix compile --warnings-as-errors`.
  - Run `mix test`.
  - Run `mix check`.
  - Update plan checkboxes and commit.
