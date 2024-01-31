defmodule Conta.Stats do
  import Ecto.Query, only: [from: 2]

  alias Conta.Projector.Stats.Income
  alias Conta.Projector.Stats.Outcome
  alias Conta.Projector.Stats.Patrimony
  alias Conta.Projector.Stats.ProfitsLoses

  alias Conta.Repo

  alias Contex.BarChart
  alias Contex.Dataset
  alias Contex.Plot

  def list_patrimony(currency, limit \\ 6)

  def list_patrimony(nil, limit) do
    from(
      p in Patrimony,
      order_by: [desc: p.year, desc: p.month],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(&adjust_currency/1)
  end

  def list_patrimony(currency, limit) when is_atom(currency) do
    from(
      p in Patrimony,
      where: p.currency == ^currency,
      order_by: [desc: p.year, desc: p.month],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(&adjust_currency/1)
  end

  defp adjust_currency(%Patrimony{currency: currency, amount: amount, balance: balance} = patrimony) do
    %Patrimony{patrimony |
      amount: Money.new(amount.amount, currency),
      balance: Money.new(balance.amount, currency)
    }
  end

  def graph_patrimony(currency) when is_atom(currency) do
    data = list_patrimony(currency, 12) |> Enum.reverse()
    headers = Enum.map(data, &to_date/1)
    options = [
      type: :stacked,
      data_labels: true,
      orientation: :vertical,
      colour_palette: :default
    ]

    data
    |> Enum.map(&[to_date(&1), Decimal.to_float(Money.to_decimal(&1.balance))])
    |> Dataset.new(headers)
    |> Plot.new(BarChart, 640, 480, options)
    |> Plot.titles("", "")
    |> Plot.axis_labels("", "")
    |> Plot.plot_options(%{legend_setting: :none})
    |> Plot.to_xml()
  end

  defp to_date({month, year}) do
    "#{year}/#{String.pad_leading(to_string(month), 2, "0")}"
  end

  defp to_date(patrimony) do
    "#{patrimony.year}/#{String.pad_leading(to_string(patrimony.month), 2, "0")}"
  end

  defp get_months(i) do
    date = Date.utc_today()
    get_months(date.month, date.year, i)
  end

  defp get_months(month, year, 1), do: {month, year}
  defp get_months(1, year, i), do: get_months(12, year-1, i-1)
  defp get_months(month, year, i), do: get_months(month-1, year, i-1)

  defp top_accounts(table, groups, months) do
    {month, year} = get_months(months)
    from(
      t in table,
      where: t.year > ^year or (t.year == ^year and t.month >= ^month),
      group_by: t.account_name,
      order_by: [desc: sum(t.balance)],
      select: t.account_name,
      limit: ^groups
    )
    |> Repo.all()
    |> Enum.map(&Enum.join(&1, "."))
  end

  def list_pnl(months, currency) do
    from(
      p in ProfitsLoses,
      where: p.currency == ^currency,
      order_by: [desc: p.year, desc: p.month],
      limit: ^months
    )
    |> Repo.all()
  end

  defp list_by_groups(table, groups, months, currency) do
    {month, year} = get_months(months)

    accounts = top_accounts(table, groups, months)

    {main, others} =
      from(
        t in table,
        where: t.year > ^year or (t.year == ^year and t.month >= ^month),
        where: t.currency == ^currency,
        group_by: [t.year, t.month, t.account_name],
        order_by: [desc: t.year, desc: t.month, asc: t.account_name],
        select: {{t.month, t.year}, t.account_name, sum(t.balance)}
      )
      |> Repo.all()
      |> Enum.map(fn {date, account_name, balance} ->
        balance = Money.new(balance.amount, currency)
        {to_date(date), to_name(account_name, accounts), balance}
      end)
      |> Enum.split_with(fn {_date, name, _balance} -> name in accounts end)

    others =
      others
      |> Enum.group_by(
        fn {date, name, _balance} -> {date, name} end,
        fn {_date, _name, balance} -> balance end
      )
      |> Enum.map(fn {{date, name}, balances} ->
        {date, name, Enum.reduce(balances, Money.new(0, currency), &Money.add/2)}
      end)

    order =
      accounts
      |> Enum.concat(["Others"])
      |> Enum.with_index()
      |> Map.new()

    (main ++ others)
    |> Enum.sort_by(fn {date, account, _balance} ->
      {date, order[account]}
    end)
  end

  def list_outcome(groups \\ 4, months \\ 12, currency \\ :EUR) do
    list_by_groups(Outcome, groups, months, currency)
  end

  def list_income(groups \\ 4, months \\ 12, currency \\ :EUR) do
    list_by_groups(Income, groups, months, currency)
  end

  defp to_name(account_name, accounts) do
    account_name = Enum.join(account_name, ".")
    if account_name in accounts do
      account_name
    else
      "Others"
    end
  end

  def graph_pnl(currency, months) when is_atom(currency) do
    data = list_pnl(months, currency)
    headers = ["Profits", "Losses", "Balance"]

    options = [
      mapping: %{
        category_col: "Months",
        value_cols: headers
      },
      type: :grouped,
      data_labels: true,
      orientation: :vertical,
      colour_palette: :default
    ]

    data
    |> Enum.map(fn pnl ->
      date = to_date({pnl.month, pnl.year})
      profits = Decimal.to_float(Money.to_decimal(pnl.profits))
      loses = Decimal.to_float(Money.to_decimal(pnl.loses))
      balance = Decimal.to_float(Money.to_decimal(pnl.balance))
      [date, profits, loses, balance]
    end)
    |> Enum.reverse()
    |> Dataset.new(["Months"|headers])
    |> Plot.new(BarChart, 640, 480, options)
    |> Plot.titles("", "")
    |> Plot.axis_labels("", "")
    |> Plot.plot_options(%{legend_setting: :legend_top})
    |> Plot.to_xml()
  end

  def graph_outcome(currency, groups \\ 4, months \\ 12) when is_atom(currency) do
    data = list_outcome(groups, months, currency)
    graph_by(Outcome, data, currency, groups, months)
  end

  def graph_income(currency, groups \\ 4, months \\ 12) when is_atom(currency) do
    data = list_income(groups, months, currency)
    graph_by(Income, data, currency, groups, months)
  end

  defp graph_by(table, data, currency, groups, months) when is_atom(currency) do
    headers = top_accounts(table, groups, months) ++ ["Others"]

    options = [
      mapping: %{
        category_col: "Months",
        value_cols: headers
      },
      type: :stacked,
      data_labels: true,
      orientation: :vertical,
      colour_palette: :default
    ]

    data
    |> Enum.group_by(
      fn {date, _name, _balance} -> date end,
      fn {_date, name, balance} -> {name, to_float(balance)} end
    )
    |> Enum.map(fn {date, values} ->
      [date|process_values(values, headers)]
    end)
    |> Dataset.new(["Months"|headers])
    |> Plot.new(BarChart, 640, 480, options)
    |> Plot.titles("", "")
    |> Plot.axis_labels("", "")
    |> Plot.plot_options(%{legend_setting: :legend_top})
    |> Plot.to_xml()
  end

  defp process_values(values, headers) do
    values = Map.new(values)
    Enum.map(headers, fn account_name ->
        values[account_name] || 0
    end)
  end

  defp to_float(money) do
    Decimal.to_float(Money.to_decimal(money))
  end
end
