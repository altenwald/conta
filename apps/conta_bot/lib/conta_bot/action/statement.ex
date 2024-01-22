defmodule ContaBot.Action.Statement do
  use ContaBot.Action

  @num_entries 20

  def statement_output(account_name) when is_list(account_name) do
    Conta.Ledger.list_entries(account_name, @num_entries)
    |> Enum.reverse()
    |> Enum.group_by(& &1.on_date)
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

  defp account_fmt(account_name) do
    (account_name || "-- Breakdown")
    |> Enum.join(".")
    |> escape_markdown()
  end

  defp currency_fmt(value) do
    value
    |> to_string()
    |> String.pad_leading(15)
    |> escape_markdown()
  end

  @impl ContaBot.Action
  def handle(:init, context) do
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
    answer(context, statement_output(String.split(account, ".")), parse_mode: "MarkdownV2")
  end
end
