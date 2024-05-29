defmodule ContaBot.Action.Pnl do
  use ContaBot.Action
  require Logger

  def pnl_output(text) do
    currency = get_currency(text)

    Conta.Stats.list_pnl(6, currency)
    |> Enum.reverse()
    |> Enum.map(fn pnl ->
      year_month = month_year_fmt(pnl.month, pnl.year)
      currency = String.pad_leading(to_string(pnl.currency), 9)
      profits = currency_fmt(pnl.profits)
      loses = currency_fmt(pnl.loses)
      balance = currency_fmt(pnl.balance)

      """
      *#{year_month} #{currency}*
      ```
      profits: #{profits}
      losses : #{loses}
      balance: #{balance}
      ```
      """
    end)
    |> then(&Enum.join(&1, "  \n\n"))
  end

  @impl ContaBot.Action
  def handle({:init, _command}, context) do
    options =
      for currency <- Conta.Ledger.list_used_currencies() do
        name = Money.Currency.name(currency)
        symbol = Money.Currency.symbol(currency)
        {"#{name} (#{symbol})", "pnl #{currency}"}
      end

    answer_select(context, "What currency do you want to use?", options)
  end

  def handle({:callback, currency}, context) do
    context
    |> delete_callback()
    |> answer(pnl_output(currency), parse_mode: "MarkdownV2")
  end
end
