# Design Spec: Dashboard Banks Candlestick Chart and SVG Web Delivery

## Status: Approved
## Date: 2026-08-26

## Summary
1. Add a monthly bank account candlestick chart (`banks`) to the dashboard, covering the last 12 months with Open, High, Low, Close (OHLC) liquidity balance data.
2. Structure the dashboard grid so the Banks candlestick chart occupies a double-width card (spanning the full 12 columns / 2 spaces on large screens) while remaining responsive on smaller screens.
3. Switch web chart delivery in `ContaWeb.DashboardController` to native SVG (`image/svg+xml`), reserving PNG generation for Telegram bot (`ContaBot.Action.Graph`) photo messages.
4. Add the new `banks` chart option to `ContaBot.Action.Graph` in PNG format.

## Goals
- In `Conta.Stats`:
  - Implement `list_banks(currency, months \\ 12)` to aggregate monthly OHLC candlestick metrics from ledger entries on bank asset accounts.
  - Implement `chart_banks(currency, months \\ 12)` using `Plotto.CandlestickChart`.
  - Implement `graph_banks(currency, months \\ 12)` returning the SVG binary.
- In `ContaWeb`:
  - Update `ContaWeb.DashboardController` to serve `image/svg+xml` using `Plotto.to_svg!/1`.
  - Update `ContaWeb.DashboardController` to recognize `banks` and `bank` chart types.
  - Update `ContaWeb.DashboardLive.Index` (`index.html.heex`) to display the new Banks candlestick chart in a double-width card (`col-span-12`).
- In `ContaBot`:
  - Add `"Banks"` option to `ContaBot.Action.Graph` menu and handle `graph banks` callback queries to deliver `banks.png`.
- Ensure comprehensive tests and zero warnings with `mix test` and `mix check`.

## Architecture & Implementation Details

### 1. Bank Account Detection & OHLC Metric Calculation (`Conta.Stats`)
- **Bank Account Matching**:
  Bank accounts are asset accounts whose hierarchy includes bank names:
  `a.type == :assets and a.currency == ^currency and (fragment("lower(?[1])", a.name) in ~w[bancos banco bank banks] or fragment("lower(?[2])", a.name) in ~w[bancos banco bank banks])`
- **Time Window**:
  Last `months` (default 12) months up to today.
  `start_date` = `Date.beginning_of_month(Date.shift(Date.utc_today(), month: -(months - 1)))`.
  `end_date` = `Date.end_of_month(Date.utc_today())`.
- **OHLC Calculation**:
  1. Starting balance prior to `start_date`: Sum of `debit - credit` for matching accounts where `on_date < ^start_date`.
  2. Query all entries for matching accounts with `on_date >= ^start_date and on_date <= ^end_date`, sorted by `[asc: on_date, asc: inserted_at]`.
  3. Iterate across each of the 12 months:
     - For month `M`:
       - `open` = running balance at beginning of month `M`.
       - For each entry in `M`:
         - `running_balance = running_balance + debit - credit`
         - `high = max(high, running_balance)`
         - `low = min(low, running_balance)`
       - `close` = running balance at end of month `M`.
       - If no entries in `M`: `open = high = low = close = previous running balance`.
       - Label = `"#{year}/#{String.pad_leading(to_string(month), 2, "0")}"`.
       - Map to `%{label: label, open: to_float(open), high: to_float(high), low: to_float(low), close: to_float(close)}`.
- **Chart Builder**:
  `Plotto.CandlestickChart.new!(data, width: 1200, height: 480)`

### 2. SVG Delivery on Web (`ContaWeb.DashboardController`)
- Endpoint: `GET /dashboard/:type/:currency`
- Controller:
  ```elixir
  def image(conn, %{"type" => type, "currency" => currency}) do
    with true <- type in ~w[outcome income pnl patrimony banks bank],
         true <- is_currency(currency) do
      svg =
        chart(type, String.to_existing_atom(currency))
        |> Plotto.to_svg!()

      conn
      |> put_resp_content_type("image/svg+xml")
      |> send_resp(200, svg)
    else
      false ->
        conn
        |> put_status(:not_found)
        |> html("Not found")
    end
  end
  ```

### 3. Dashboard Layout (`ContaWeb.DashboardLive`)
- The grid uses `grid-cols-12 gap-6`.
- Standard cards use `col-span-12 lg:col-span-6` (2 columns per row on desktop).
- The new Banks candlestick card uses `col-span-12` (spanning both columns / full width on desktop, and 100% width on mobile).
- Structure:
  ```heex
  <div class="col-span-12">
    <div class="card bg-base-100 shadow-xl border border-base-200">
      <div class="bg-base-200 px-4 py-3 border-b border-base-300 rounded-t-2xl">
        <h2 class="card-title text-base m-0">
          {gettext("Banks")}
        </h2>
      </div>
      <div class="card-body p-6">
        <img src={~p"/dashboard/banks/#{@currency}"} alt="Banks chart" class="w-full h-auto" />
      </div>
    </div>
  </div>
  ```

### 4. Telegram Bot PNG Generation (`ContaBot.Action.Graph`)
- In `ContaBot.Action.Graph`:
  - Add `{"Banks", "graph banks"}` to `{:init, _command}` options.
  - Implement `handle({:callback, "banks"}, context)` to prompt for currency.
  - Implement `handle({:callback, "banks " <> currency}, context)` calling `Conta.Stats.chart_banks/1 |> Plotto.to_png() |> ExGram.send_photo(...)`.
