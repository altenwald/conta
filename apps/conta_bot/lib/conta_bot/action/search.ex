defmodule ContaBot.Action.Search do
  use ContaBot.Action

  @num_entries 20

  def statement_output(search) do
    Conta.Ledger.list_entries_by(search, @num_entries)
    |> Enum.group_by(& &1.transaction_id)
    |> Enum.sort_by(fn {_transaction_id, [entry | _]} -> entry.on_date end, {:asc, Date})
    |> Enum.map(fn {_transaction_id, [entry | _] = entries} ->
      header =
        """
        \\-\\-\\-\\-\\-
        *#{escape_markdown(to_string(entry.on_date))}*
        _#{escape_markdown(entry.description)}_

        ```
        """

      body =
        entries
        |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})
        |> Enum.map(fn entry ->
          """
          #{account_fmt(entry.account_name)}
          #{currency_fmt(entry.debit)} #{currency_fmt(entry.credit)}
          """
        end)

      [header | body] ++ ["```"]
    end)
    |> to_string()
  end

  @impl ContaBot.Action
  def handle(:init, context) do
    answer_me(context, "Write the text to search...")
  end

  def handle({:text, search}, context) do
    case statement_output(search) do
      "" ->
        answer(context, "Not found entries with that description")

      response ->
        answer(context, response, parse_mode: "MarkdownV2")
    end
  end
end
