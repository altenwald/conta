defmodule ContaBot.Action.Status do
  use ContaBot.Action

  @default_depth 2

  defp get_depth(text) do
    case Regex.run(~r/([0-9]+)/, text, capture: :all_but_first) do
      [n] -> String.to_integer(n)
      nil -> @default_depth
    end
  end

  def status_output(text) do
    Conta.Ledger.list_accounts("assets", get_depth(text))
    |> Enum.map(fn account ->
      balances = Enum.reject(account.balances, &Money.zero?(&1.amount))
      Map.put(account, :balances, balances)
    end)
    |> Enum.reject(&Enum.empty?(&1.balances))
    |> Enum.map(&{Enum.join(&1.name, "."), &1.balances})
    |> Enum.map_join(fn {name, balances} ->
      Enum.reduce(balances, "*#{escape_markdown(name)}*  \n```\n", fn balance, acc ->
        money = Money.new(balance.amount.amount, balance.currency)
        acc <> currency_fmt(money) <> "  \n"
      end) <> "```\n"
    end)
  end

  @impl ContaBot.Action
  def handle(:init, context) do
    options = [
      {"Depth 2 (i.e. Active.Bank)", "status 2"},
      {"Depth 3 (i.e. Active.Bank.ING)", "status 3"}
    ]

    answer_select(context, "What's the depth you want?", options, [])
  end

  def handle({:callback, depth}, context) do
    context
    |> delete_callback()
    |> answer(status_output(depth), parse_mode: "MarkdownV2")
  end
end
