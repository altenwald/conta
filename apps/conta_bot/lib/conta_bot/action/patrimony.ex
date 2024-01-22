defmodule ContaBot.Action.Patrimony do
  use ContaBot.Action
  require Logger

  defp get_currency(text) do
    currencies = Conta.Ledger.currencies()

    if match = Regex.run(~r/([A-Z]{3})/, text, capture: :all_but_first) do
      try do
        currency = String.to_existing_atom(hd(match))
        if currency in currencies, do: currency
      rescue
        ArgumentError ->
          Logger.error("non existing atom #{hd(match)}")
          nil
      end
    end
  end

  def patrimony_output(text) do
    filter_currency = get_currency(text)

    Conta.Stats.list_patrimony(filter_currency)
    |> Enum.map(fn patrimony ->
      month = String.pad_leading(to_string(patrimony.month), 2, "0")

      header =
        if filter_currency do
          "*#{patrimony.year}/#{month}*"
        else
          currency = String.pad_leading(to_string(patrimony.currency), 9)
          "*#{patrimony.year}/#{month} #{currency}*"
        end

      amount = String.pad_leading(to_string(patrimony.amount), 15, " ")
      balance = String.pad_leading(to_string(patrimony.balance), 15, " ")

      """
      #{header}
      ```
      change : #{amount}
      balance: #{balance}
      ```
      """
    end)
    |> then(&Enum.join(&1, "  \n\n"))
    |> then(&Regex.replace(~r/\./, &1, "\\.", global: true))
    |> then(&Regex.replace(~r/-/, &1, "\\-", global: true))
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
    answer(context, patrimony_output(currency), parse_mode: "MarkdownV2")
  end
end
