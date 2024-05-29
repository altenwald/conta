defmodule ContaBot.Action.Statement do
  use ContaBot.Action

  @num_entries 20

  def statement_output(account_name) when is_list(account_name) do
    Conta.Ledger.list_entries(account_name, @num_entries)
    |> Enum.reverse()
    |> Enum.group_by(&to_string(&1.on_date))
    |> Enum.map(fn {on_date, entries} ->
      entries
      |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})
      |> Enum.map(fn entry ->
        """
        *#{escape_markdown(entry.description)}*
        _#{account_fmt(entry.related_account_name || ["-- Breakdown"])}_
        ```
        #{currency_fmt(entry.credit)} credit
        #{currency_fmt(entry.debit)} debit
        #{currency_fmt(entry.balance)} balance
        ```
        """
      end)
      |> then(&"\n*#{escape_markdown(to_string(on_date))}*\n\n#{&1}")
    end)
    |> to_string()
  end

  @impl ContaBot.Action
  def handle({:init, _command}, context) do
    choose_account(context, "statement", "Choose an account", false, "")
  end

  def handle({:callback, account}, context) do
    choose_account(
      context,
      "statement",
      "Choose an account",
      false,
      "statement #{account}",
      account
    )
  end

  def handle({:event, account}, context) do
    context
    |> delete_callback()
    |> answer(statement_output(String.split(account, ".")), parse_mode: "MarkdownV2")
  end
end
