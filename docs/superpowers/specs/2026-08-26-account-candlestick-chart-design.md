# Account Candlestick (OHLC) Chart Design

## Overview

Add an interactive monthly candlestick (OHLC) chart to the account view (`/ledger/accounts/:account_id` in `AccountLive.Show`) displaying the account balance evolution across the last 12 months, matching the styling and tooltip interaction of the dashboard banks chart.

## Sign Convention by Account Type

In double-entry bookkeeping, account types have distinct normal balance signs:
- **Debit-normal accounts** (`:assets`, `:expenses`):
  Balance delta = `debit - credit`
- **Credit-normal accounts** (`:liabilities`, `:revenue`, `:equity`):
  Balance delta = `credit - debit`

By applying this normal sign rule, accounts with credit balances (such as revenue/sales, liabilities/loans, or equity) display positive evolution instead of negative values.

## Domain & Stats Context (`Conta.Stats`)

Add functions in `Conta.Stats`:
- `list_account(account, months \\ 12)`: Computes OHLC dataset for `account` (matching `account.name` and any subaccounts).
- `chart_account(account, months \\ 12)`: Builds `Plotto.CandlestickChart` struct.
- `graph_account(account, months \\ 12, theme \\ :system)`: Generates SVG binary with theme style injection.

## Web Interface (`ContaWeb.AccountLive.Show`)

In `apps/conta_web/lib/conta_web/live/account_live/show.html.heex`:
- Place a card above the account details containing the candlestick chart.
- Card header: "Evolution" (`gettext("Evolution")`).
- Hook `phx-hook="ChartTooltip"` and `.chart-container` class for responsive layout and tooltip interaction in both light and dark mode.
