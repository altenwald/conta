defmodule ContaBot.Action.Statement do
  use ContaBot.Action
  alias ContaBot.Action.Transaction
  alias ContaBot.Action.Transaction.Worker

  @num_entries 20

  defp uuid_to_int36(uuid) when is_binary(uuid) do
    <<uuid_int::integer-size(128)>> = Ecto.UUID.dump!(uuid)
    Integer.to_string(uuid_int, 36)
  end

  defp int36_to_uuid(uuid_int) when is_binary(uuid_int) do
    uuid_int = String.to_integer(uuid_int, 36)
    Ecto.UUID.load!(<<uuid_int::integer-size(128)>>)
  end

  def statement_output(account_name) when is_list(account_name) do
    match_me(~r/^dup_[0-9A-Z]+$/)
    match_me(~r/^rem_[0-9A-Z]+$/)

    Conta.Ledger.list_entries(account_name, @num_entries)
    |> Enum.reverse()
    |> Enum.group_by(&to_string(&1.on_date))
    |> Enum.map(fn {on_date, entries} ->
      entries
      |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})
      |> Enum.map(fn entry ->
        transaction_id = uuid_to_int36(entry.transaction_id)

        """
        *#{escape_markdown(entry.description)}*
        _#{account_fmt(entry.related_account_name || ["-- Breakdown"])}_
        /dup\\_#{transaction_id}
        /rem\\_#{transaction_id}
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
  def handle({:init, "statement"}, context) do
    choose_account(context, "statement", "Choose an account", false, "")
  end

  def handle({:init, <<"dup_", uuid_int_str::binary>>}, context) do
    transaction_id = int36_to_uuid(uuid_int_str)

    case Conta.Ledger.get_entries_by_transaction_id(transaction_id) do
      [entry1, entry2] ->
        chat_id = get_chat_id(context)
        if Worker.exists?(chat_id), do: Worker.stop(chat_id)
        # TODO based on the account type it could be credit for positive or
        # negative values of amount.
        amount = Money.subtract(entry1.debit, entry1.credit) |> Money.to_decimal()
        {:ok, _pid} = Worker.start(chat_id)
        {:ok, _} = Worker.call(chat_id, {:callback, Enum.join(entry1.account_name, ".")})
        {:ok, _} = Worker.call(chat_id, {:event, "description"})
        {:ok, _} = Worker.call(chat_id, {:text, entry1.description})
        {:ok, _} = Worker.call(chat_id, {:callback, Enum.join(entry2.account_name, ".")})
        {:ok, _} = Worker.call(chat_id, {:event, "amount"})
        {:ok, _} = Worker.call(chat_id, {:text, to_string(amount)})
        Transaction.handle({:text, to_string(entry1.on_date)}, context)

      [] ->
        answer(context, "not found transaction #{transaction_id}")

      _ ->
        # TODO support for complex transactions
        answer(context, "we've still not support for complex transactions")
    end
  end

  def handle({:init, <<"rem_", uuid_int_str::binary>>}, context) do
    transaction_id = int36_to_uuid(uuid_int_str)

    case Conta.Ledger.get_entries_by_transaction_id(transaction_id) do
      [] ->
        answer(context, "not found transaction #{transaction_id}")

      [entry | _] = entries ->
        answer_select(
          context,
          """
          Are you sure you want to remove it?

          *#{escape_markdown(to_string(entry.on_date))}*
          """ <> format_data(entries),
          [
            {"Confirm", "statement remove confirm #{transaction_id}"},
            {"Cancel", "statement remove cancel"}
          ],
          [],
          parse_mode: "MarkdownV2"
        )
    end
  end

  def handle({:callback, "remove cancel"}, context) do
    delete_callback(context)
  end

  def handle({:callback, "remove confirm " <> transaction_id}, context) do
    :ok = Conta.Ledger.delete_account_transaction(transaction_id)

    context
    |> delete_callback()
    |> answer("Transaction removed")
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

  defp format_data(entries) do
    Enum.map_join(entries, fn entry ->
      """
      ```
      credit : #{escape_markdown(String.pad_leading(to_string(entry.credit), 15))}
      debit  : #{escape_markdown(String.pad_leading(to_string(entry.debit), 15))}
      ```
      *Account* #{escape_markdown(Enum.join(entry.account_name, "."))}
      *Description* #{escape_markdown(entry.description)}
      """
    end)
  end
end
