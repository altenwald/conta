defmodule ContaBot.Action.Search do
  use ContaBot.Action

  @num_entries 20

  def statement_output(search) do
    Conta.Ledger.list_entries_by(search, @num_entries)
    |> Enum.reverse()
    |> Enum.group_by(& &1.transaction_id)
    |> Enum.map(fn {_transaction_id, entries} ->
      entries
      |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})
      |> Enum.map(fn entry ->
        """
        *#{escape_markdown(to_string(entry.on_date))}*

        *#{escape_markdown(entry.description)}*
        _#{account_fmt(entry.account_name)}_
        ```
        #{currency_fmt(entry.credit)} credit
        #{currency_fmt(entry.debit)} debit
        ```
        """
      end)
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
