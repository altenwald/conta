# Telegram Bot Candle Chart Command Design

## 1. Overview and Goal

Backlog Task #19 requests adding a candlestick chart command (`/candle`) to the Telegram bot (`apps/conta_bot`) for monthly account balance overviews.
- Users can view monthly financial candlestick charts (Open, High, Low, Close balances) directly in Telegram as PNG images.
- Plotto (`Plotto.CandlestickChart` + `Plotto.to_png/1`) renders the charts.
- `Conta.Stats.chart_account/2` already builds the candlestick chart from `Conta.Ledger`.

## 2. User Interactions and Conversational Flow

The bot will support two usage patterns:

### A. Direct Command (with arguments)
```
/candle Assets.Banks.Checking
/candle Assets.Banks.Checking 6
```
- Argument 1: Account name in dotted notation (e.g. `Assets.Banks.Checking`).
- Argument 2 (optional): Number of months (integer > 0). Defaults to 12 months.
- Behavior:
  - If account exists: generates candlestick chart, renders PNG, and sends as photo message.
  - If account does not exist: responds with error message `"Account <name> not found"`.
  - If invalid months: responds with error message `"Invalid number of months"`.

### B. Interactive Flow (without arguments)
1. User types `/candle`.
2. Bot presents top-level account categories (Assets, Liabilities, Equity, Expenses, Revenue) via inline keyboard buttons using `choose_account/5`.
3. User drills down into subcategories (e.g. `Assets` -> `Banks` -> `Checking`).
4. User selects "Continue with <Account>..." (via `{:event, account}`).
5. Bot asks for time range:
   - "Choose period for <Account> (default 12 months):"
   - Inline keyboard options:
     - `3 months` -> callback `"candle months <account> 3"`
     - `6 months` -> callback `"candle months <account> 6"`
     - `12 months (1 year)` -> callback `"candle months <account> 12"`
     - `24 months (2 years)` -> callback `"candle months <account> 24"`
6. User taps a duration button:
   - Bot deletes callback message.
   - Generates chart for `<account>` over `<months>`.
   - Sends photo message to the chat with caption `"Candle chart for <account> (<months> months)"`.

### C. Direct Text Input
If text arrives while awaiting input for candle (or as a message), the bot can accept `<account> [months]` text.

## 3. Architecture and Component Design

### 3.1 Domain Layer (`apps/conta/lib/conta/stats.ex`)
Currently, `Conta.Stats.list_account/2` supports `%Account{}` structs and UUID binary strings.
We extend `list_account/2` to accept:
- Binary dotted account names (e.g. `"Assets.Banks.Checking"`): looked up via `Conta.Ledger.get_account_by_name(String.split(account, "."))`.
- Account name lists (e.g. `["Assets", "Banks", "Checking"]`): looked up via `Conta.Ledger.get_account_by_name(account)`.
- If account not found: returns empty list `[]` or raises/handles cleanly.

### 3.2 Bot Action Registration (`apps/conta_bot/lib/conta_bot/action.ex`)
Add command definition:
```elixir
command("candle", description: "Get candle chart for an account")
```
When `/candle` is dispatched:
- `handle({:command, :candle, params}, context)` forwards to `ContaBot.Action.Candle`.

### 3.3 Bot Action Module (`apps/conta_bot/lib/conta_bot/action/candle.ex`)
Implements `ContaBot.Action` behaviour:
- `handle({:init, "candle"}, context)`: checks `context.update.message.text` for arguments. If arguments present, executes direct command. Otherwise, initiates `choose_account/5`.
- `handle({:callback, account}, context)`: drills into sub-accounts via `choose_account/6`.
- `handle({:event, account}, context)`: prompts user to select time period (3, 6, 12, 24 months).
- `handle({:callback, "months " <> data}, context)`: parses account and months, builds chart, converts to PNG via `Plotto.to_png/1`, dispatches photo, and cleans up callback message.
- `handle({:text, text}, context)`: parses `<account> [months]` and generates chart.

Photo dispatch is configurable via `@bot_api Application.compile_env(:conta_bot, :bot_api, ExGram)` to support deterministic, offline unit testing.

## 4. Testing Strategy

1. `apps/conta/test/conta/stats_test.exs`:
   - Verify `Conta.Stats.chart_account/2` with string dotted name `"Assets.Savings"` and string list `~w[Assets Savings]`.
2. `apps/conta_bot/test/conta_bot/action/candle_test.exs`:
   - Test `handle({:init, "candle"}, context)` without args initiates account selection keyboard.
   - Test `handle({:init, "candle"}, context)` with `/candle Assets.Savings 6` generates chart and dispatches photo.
   - Test `handle({:callback, "Assets"}, context)` drills down child accounts.
   - Test `handle({:event, "Assets.Savings"}, context)` asks for months.
   - Test `handle({:callback, "months Assets.Savings 12"}, context)` sends chart photo.
   - Test unknown account handling sends error message.
