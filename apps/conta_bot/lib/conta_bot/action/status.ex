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
      balances = Enum.reject(account.balances, fn {_, amount} -> amount == 0 end)
      Map.put(account, :balances, Map.new(balances))
    end)
    |> Enum.reject(&(&1.balances == %{}))
    |> Enum.map(&{Enum.join(&1.name, "."), &1.balances})
    |> Enum.map(fn {name, balances} ->
      Enum.reduce(balances, "*#{name}*  \n```\n", fn {currency, amount}, acc ->
        acc <> String.pad_leading(to_string(Money.new(amount, currency)), 15) <> "  \n"
      end) <> "```\n"
    end)
    |> Enum.join()
    |> then(&Regex.replace(~r/\./, &1, "\\.", global: true))
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
    answer(context, status_output(depth), parse_mode: "MarkdownV2")
  end
end
