defmodule ContaBot.Action.Patrimony do
  use ContaBot.Action
  require Logger

  def patrimony_output(text) do
    filter_currency = get_currency(text)

    Conta.Stats.list_patrimony(filter_currency)
    |> Enum.map(fn patrimony ->
      year_month = month_year_fmt(patrimony.month, patrimony.year)

      header =
        if filter_currency do
          "*#{year_month}*"
        else
          currency = String.pad_leading(to_string(patrimony.currency), 9)
          "*#{year_month} #{currency}*"
        end

      amount = currency_fmt(patrimony.amount)
      balance = currency_fmt(patrimony.balance)

      """
      #{header}
      ```
      change : #{amount}
      balance: #{balance}
      ```
      """
    end)
    |> then(&Enum.join(&1, "  \n\n"))
  end

  @impl ContaBot.Action
  def handle(:init, context) do
    options =
      for currency <- Conta.Ledger.currencies() do
        name = Money.Currency.name(currency)
        symbol = Money.Currency.symbol(currency)
        {"#{name} (#{symbol})", "patrimony #{currency}"}
      end

    extra = [{"All of them", "patrimony "}]
    answer_select(context, "What currency do you want to use?", options, extra)
  end

  def handle({:callback, currency}, context) do
    context
    |> delete_callback()
    |> answer(patrimony_output(currency), parse_mode: "MarkdownV2")
  end
end
