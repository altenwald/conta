defmodule ContaBot.Action.Outcome do
  use ContaBot.Action
  require Logger

  def outcome_output(text) do
    currency = get_currency(text)

    Conta.Stats.list_outcome(4, 6, currency)
    |> Enum.group_by(
      fn {date, _name, _balance} -> date end,
      fn {_date, name, balance} -> %{name: name, balance: balance} end
    )
    |> Enum.map(fn {date, entries} ->
      entries
      |> Enum.map(fn entry ->
        """
        *#{escape_markdown(entry.name)}*
        ```
        #{currency_fmt(entry.balance)} balance
        ```
        """
      end)
      |> then(&"\n*#{escape_markdown(to_string(date))}*\n\n#{&1}")
    end)
    |> to_string()
  end

  @impl ContaBot.Action
  def handle({:init, _command}, context) do
    options =
      for currency <- Conta.Ledger.list_used_currencies() do
        name = Money.Currency.name(currency)
        symbol = Money.Currency.symbol(currency)
        {"#{name} (#{symbol})", "outcome #{currency}"}
      end

    answer_select(context, "What currency do you want to use?", options)
  end

  def handle({:callback, currency}, context) do
    context
    |> delete_callback()
    |> answer(outcome_output(currency), parse_mode: "MarkdownV2")
  end
end
