defmodule Conta.StatsTest do
  use Conta.DataCase, async: true
  import Conta.LedgerFixtures

  alias Conta.Stats

  describe "patrimony graphs" do
    test "chart_patrimony/1 configures y_guidelines and graph_patrimony/1 generates SVG" do
      chart = Stats.chart_patrimony(:EUR)
      assert match?({:dotted, _}, chart.opts.y_guidelines)

      svg = Stats.graph_patrimony(:EUR)
      assert is_binary(svg)
      assert String.starts_with?(svg, "<svg")
      assert svg =~ "<rect"
      assert svg =~ "plotto-guideline"
    end
  end

  describe "pnl graphs" do
    test "chart_pnl/2 configures horizontal top legend and y_guidelines" do
      chart = Stats.chart_pnl(:EUR, 6)
      assert chart.opts.legend == :top
      assert chart.opts.legend_orientation == :horizontal
      assert match?({:dotted, _}, chart.opts.y_guidelines)

      svg = Stats.graph_pnl(:EUR, 6)
      assert is_binary(svg)
      assert String.starts_with?(svg, "<svg")
      assert svg =~ "<rect"
      assert svg =~ "plotto-guideline"
    end
  end

  describe "income and outcome graphs" do
    test "chart_income/3 configures horizontal top legend and y_guidelines" do
      chart = Stats.chart_income(:EUR, 4, 12)
      assert chart.opts.legend == :top
      assert chart.opts.legend_orientation == :horizontal
      assert match?({:dotted, _}, chart.opts.y_guidelines)

      svg = Stats.graph_income(:EUR, 4, 12)
      assert is_binary(svg)
      assert String.starts_with?(svg, "<svg")
      assert svg =~ "plotto-guideline"
    end

    test "chart_outcome/3 configures horizontal top legend and y_guidelines" do
      chart = Stats.chart_outcome(:EUR, 4, 12)
      assert chart.opts.legend == :top
      assert chart.opts.legend_orientation == :horizontal
      assert match?({:dotted, _}, chart.opts.y_guidelines)

      svg = Stats.graph_outcome(:EUR, 4, 12)
      assert is_binary(svg)
      assert String.starts_with?(svg, "<svg")
      assert svg =~ "plotto-guideline"
    end
  end

  describe "banks candlestick graphs" do
    test "list_banks/2 returns 12 months with 0s when no bank accounts or entries exist" do
      items = Stats.list_banks(:EUR, 12)
      assert length(items) == 12

      assert Enum.all?(items, fn item ->
               Map.has_key?(item, :label) and
                 item.open == 0.0 and item.high == 0.0 and item.low == 0.0 and item.close == 0.0
             end)
    end

    test "list_banks/2 calculates OHLC metrics across bank accounts" do
      _account = insert(:account, %{name: ~w[Assets Bank], type: :assets, currency: :EUR})

      today = Date.utc_today()
      this_month = Date.beginning_of_month(today)
      prev_month = Date.beginning_of_month(Date.shift(today, month: -1))

      # Prior entry in previous month
      insert(:entry, %{
        account_name: ~w[Assets Bank],
        on_date: prev_month,
        debit: 1_000_00,
        credit: 0,
        balance: 1_000_00
      })

      # Entry 1 in this month: +500 (balance becomes 1500)
      insert(:entry, %{
        account_name: ~w[Assets Bank],
        on_date: this_month,
        debit: 500_00,
        credit: 0,
        balance: 1_500_00
      })

      # Entry 2 in this month: -200 (balance becomes 1300)
      insert(:entry, %{
        account_name: ~w[Assets Bank],
        on_date: this_month,
        debit: 0,
        credit: 200_00,
        balance: 1_300_00
      })

      items = Stats.list_banks(:EUR, 2)
      assert length(items) == 2

      [prev_data, this_data] = items

      assert prev_data.open == 0.0
      assert prev_data.high == 1000.0
      assert prev_data.low == 0.0
      assert prev_data.close == 1000.0

      assert this_data.open == 1000.0
      assert this_data.high == 1500.0
      assert this_data.low == 1000.0
      assert this_data.close == 1300.0
    end

    test "chart_banks/2 creates Plotto.CandlestickChart struct with y_guidelines" do
      chart = Stats.chart_banks(:EUR, 12)
      assert %Plotto.CandlestickChart{} = chart
      assert match?({:dotted, _}, chart.opts.y_guidelines)
    end

    test "graph_banks/2 generates SVG binary with guidelines" do
      svg = Stats.graph_banks(:EUR, 12)
      assert is_binary(svg)
      assert String.starts_with?(svg, "<svg")
      assert svg =~ "plotto-guideline"
    end
  end

  describe "account candlestick graphs" do
    test "list_account/2 returns empty OHLC metrics when no entries exist" do
      account = insert(:account, %{name: ~w[Assets Cash], type: :assets, currency: :EUR})
      items = Stats.list_account(account, 12)
      assert length(items) == 12

      assert Enum.all?(items, fn item ->
               Map.has_key?(item, :label) and
                 item.open == 0.0 and item.high == 0.0 and item.low == 0.0 and item.close == 0.0 and
                 item.diff == 0.0
             end)
    end

    test "list_account/2 computes OHLC for assets account with debit positive" do
      account = insert(:account, %{name: ~w[Assets Cash], type: :assets, currency: :EUR})
      today = Date.utc_today()
      this_month = Date.beginning_of_month(today)
      prev_month = Date.beginning_of_month(Date.shift(today, month: -1))

      insert(:entry, %{
        account_name: ~w[Assets Cash],
        on_date: prev_month,
        debit: 800_00,
        credit: 0,
        balance: 800_00
      })

      insert(:entry, %{
        account_name: ~w[Assets Cash],
        on_date: this_month,
        debit: 400_00,
        credit: 0,
        balance: 1_200_00
      })

      insert(:entry, %{
        account_name: ~w[Assets Cash],
        on_date: this_month,
        debit: 0,
        credit: 100_00,
        balance: 1_100_00
      })

      items = Stats.list_account(account, 2)
      assert length(items) == 2

      [prev_data, this_data] = items
      assert prev_data.open == 0.0
      assert prev_data.high == 800.0
      assert prev_data.low == 0.0
      assert prev_data.close == 800.0
      assert prev_data.diff == 800.0

      assert this_data.open == 800.0
      assert this_data.high == 1200.0
      assert this_data.low == 800.0
      assert this_data.close == 1100.0
      assert this_data.diff == 300.0
    end

    test "list_account/2 computes OHLC for revenue account with credit positive" do
      account = insert(:account, %{name: ~w[Revenue Sales], type: :revenue, currency: :EUR})
      today = Date.utc_today()
      this_month = Date.beginning_of_month(today)

      # Credit 2000 (increases revenue), Debit 200 (refund)
      insert(:entry, %{
        account_name: ~w[Revenue Sales],
        on_date: this_month,
        debit: 0,
        credit: 2_000_00,
        balance: 2_000_00
      })

      insert(:entry, %{
        account_name: ~w[Revenue Sales],
        on_date: this_month,
        debit: 200_00,
        credit: 0,
        balance: 1_800_00
      })

      items = Stats.list_account(account, 1)
      assert length(items) == 1

      [this_data] = items
      assert this_data.open == 0.0
      assert this_data.high == 2000.0
      assert this_data.low == 0.0
      assert this_data.close == 1800.0
      assert this_data.diff == 1800.0
    end

    test "list_account/2 includes subaccount entries" do
      parent = insert(:account, %{name: ~w[Expenses], type: :expenses, currency: :EUR})
      _child = insert(:account, %{name: ~w[Expenses Food], type: :expenses, currency: :EUR})
      today = Date.utc_today()
      this_month = Date.beginning_of_month(today)

      insert(:entry, %{
        account_name: ~w[Expenses Food],
        on_date: this_month,
        debit: 150_00,
        credit: 0,
        balance: 150_00
      })

      items = Stats.list_account(parent, 1)
      assert length(items) == 1
      [data] = items
      assert data.close == 150.0
      assert data.diff == 150.0
    end

    test "chart_account/2 and graph_account/3 create chart and SVG with tooltip diff and guidelines" do
      account = insert(:account, %{name: ~w[Assets Savings], type: :assets, currency: :EUR})
      chart = Stats.chart_account(account, 6)
      assert %Plotto.CandlestickChart{} = chart
      assert match?({:dotted, _}, chart.opts.y_guidelines)

      svg = Stats.graph_account(account, 6)
      assert is_binary(svg)
      assert String.starts_with?(svg, "<svg")
      assert svg =~ "Diff:"
      assert svg =~ "plotto-guideline"
    end

    test "chart_account/2 and graph_account/3 work for non-EUR accounts (e.g. USD)" do
      account = insert(:account, %{name: ~w[Assets Wise USD], type: :assets, currency: :USD})
      today = Date.utc_today()
      this_month = Date.beginning_of_month(today)

      insert(:entry, %{
        account_name: ~w[Assets Wise USD],
        on_date: this_month,
        debit: 500_00,
        credit: 100_00,
        balance: 400_00
      })

      chart = Stats.chart_account(account, 1)
      assert %Plotto.CandlestickChart{} = chart
      assert match?({:dotted, _}, chart.opts.y_guidelines)

      svg = Stats.graph_account(account, 1)
      assert is_binary(svg)
      assert String.starts_with?(svg, "<svg")
      assert svg =~ "plotto-guideline"
    end
  end

  describe "inject_theme_style/2" do
    test "injects subtle line.plotto-guideline styles for dark theme" do
      svg = "<svg><rect width=\"10\" height=\"10\"/></svg>"
      styled = Stats.inject_theme_style(svg, :dark)

      assert styled =~ "line.plotto-guideline"
      assert styled =~ "#374151"
      assert styled =~ "line.plotto-axis"
    end

    test "injects subtle line.plotto-guideline styles for light theme" do
      svg = "<svg><rect width=\"10\" height=\"10\"/></svg>"
      styled = Stats.inject_theme_style(svg, :light)

      assert styled =~ "line.plotto-guideline"
      assert styled =~ "#E5E7EB"
      assert styled =~ "line.plotto-axis"
    end

    test "injects subtle line.plotto-guideline styles for system theme with prefers-color-scheme" do
      svg = "<svg><rect width=\"10\" height=\"10\"/></svg>"
      styled = Stats.inject_theme_style(svg, :system)

      assert styled =~ "line.plotto-guideline"
      assert styled =~ "#E5E7EB"
      assert styled =~ "@media(prefers-color-scheme:dark)"
      assert styled =~ "#374151"
    end
  end
end
