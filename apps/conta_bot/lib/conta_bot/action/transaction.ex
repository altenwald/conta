defmodule ContaBot.Action.Transaction do
  use ContaBot.Action
  require Logger
  alias ContaBot.Action.Transaction.Worker

  @impl ContaBot.Action
  def handle(:init, context) do
    chat_id = get_chat_id(context)
    :ok = Worker.stop(chat_id)
    {:ok, _pid} = Worker.start(chat_id)
    response({:ok, :account_name}, context)
  end

  def handle(event, context) do
    context
    |> get_chat_id()
    |> Worker.call(event)
    |> response(context)
  end

  defp response({:ok, :account_name}, context) do
    sticky = Worker.get_sticky(get_chat_id(context), :account_name)

    choose_account(
      context,
      "transaction",
      "Choose account where add the transaction",
      sticky,
      "transaction description"
    )
  end

  defp response({:ok, {:account_name, account}}, context) do
    sticky = Worker.get_sticky(get_chat_id(context), :account_name)

    choose_account(
      context,
      "transaction",
      "Choose account where add the transaction",
      sticky,
      "transaction description",
      account
    )
  end

  defp response({:ok, :description}, context) do
    answer_me(context, "Write the description")
  end

  defp response({:ok, :relative_account_name}, context) do
    sticky = Worker.get_sticky(get_chat_id(context), :relative_account_name)

    choose_account(
      context,
      "transaction",
      "Choose relative account where add the transaction",
      sticky,
      "transaction amount"
    )
  end

  defp response({:ok, {:relative_account_name, account}}, context) do
    sticky = Worker.get_sticky(get_chat_id(context), :relative_account_name)

    choose_account(
      context,
      "transaction",
      "Choose relative account where add the transaction",
      sticky,
      "transaction amount",
      account
    )
  end

  defp response({:ok, :amount}, context) do
    answer_me(context, "Write the amount using dot (.) as separator and 2 decimals")
  end

  defp response({:ok, :on_date}, context) do
    put_following_text("transaction")

    answer_select(
      context,
      "Write or choose date for the entry (YYYY-MM-DD)",
      [
        {"Today", "transaction on_date #{Date.utc_today()}"},
        {"Yesterday", "transaction on_date #{Date.add(Date.utc_today(), -1)}"}
      ],
      if sticky = Worker.get_sticky(get_chat_id(context), :on_date) do
        [{"Last used: #{sticky}", "transaction on_date #{sticky}"}]
      else
        []
      end
    )
  end

  defp response({:ok, {:confirm, data}}, context) do
    case format_data(data) do
      {:ok, data} ->
        answer_select(
          context,
          """
          Check the following data

          *#{escape_markdown(to_string(data.on_date))}*
          """ <> entries_to_string(data.entries),
          [
            {"Confirm", "transaction confirm"},
            {"Change account name", "transaction account_name"},
            {"Change description", "transaction description"},
            {"Change relative account name", "transaction relative_account_name"},
            {"Change amount", "transaction amount"},
            {"Change date", "transaction on_date"}
          ],
          [],
          parse_mode: "MarkdownV2"
        )

      {:error, message} ->
        answer(context, message)
    end
  end

  defp response({:ok, data}, context) when is_map(data) do
    chat_id = get_chat_id(context)
    {:ok, :done, data} = Worker.call(chat_id, :get_data)
    answer(context, transaction_create(data))
  end

  defp response({:error, :invalid_date}, context) do
    context
    |> answer_me("Invalid date, i.e. #{Date.utc_today()}")
    |> answer_select(
      "Write or choose date for the entry (YYYY-MM-DD)",
      [
        {"Today", "transaction on_date #{Date.utc_today()}"},
        {"Yesterday", "transaction on_date #{Date.add(Date.utc_today(), -1)}"}
      ],
      if sticky = Worker.get_sticky(get_chat_id(context), :on_date) do
        [{"Last used: #{sticky}", "transaction on_date #{sticky}"}]
      else
        []
      end
    )
  end

  defp response({:error, :invalid_amount}, context) do
    context
    |> answer("Invalid amount use i.e. 10.00")
    |> answer_me("Write the amount using dot (.) as separator and 2 decimals")
  end

  defp response({:error, :invalid_event}, context) do
    answer(context, "Invalid event")
  end

  defp entries_to_string(entries) do
    Enum.reduce(entries, "", fn entry, acc ->
      """
      #{acc}
      ```
      credit : #{escape_markdown(String.pad_leading(to_string(entry.credit / 100.0), 15))}
      debit  : #{escape_markdown(String.pad_leading(to_string(entry.debit / 100.0), 15))}
      ```
      *Account* #{escape_markdown(Enum.join(entry.account_name, "."))}
      *Description* #{escape_markdown(entry.description)}
      """
    end)
  end

  defp format_data(data) do
    Logger.debug("creating transaction for data: #{inspect(data)}")
    account_name = String.split(data.account_name, ".")
    relative_account_name = String.split(data.relative_account_name, ".")

    with {:ok, account} <- Conta.Ledger.get_account_by_name(account_name),
         {:ok, relative_account} <- Conta.Ledger.get_account_by_name(relative_account_name),
         {:currency, true} <- {:currency, account.currency == relative_account.currency} do
      {add_account, add_relative_account} =
        if data.amount > 0 do
          {
            &Map.merge(&1, %{debit: abs(data.amount), credit: 0}),
            &Map.merge(&1, %{credit: abs(data.amount), debit: 0})
          }
        else
          {
            &Map.merge(&1, %{credit: abs(data.amount), debit: 0}),
            &Map.merge(&1, %{debit: abs(data.amount), credit: 0})
          }
        end

      entries = [
        add_account.(%{
          description: data.description,
          account_name: account_name,
          change_currency: relative_account.currency
        }),
        add_relative_account.(%{
          description: data.description,
          account_name: relative_account_name,
          change_currency: account.currency
        })
      ]

      {:ok, %{on_date: data.on_date, entries: entries}}
    else
      {:error, _} ->
        {:error, "Account doesn't exist"}

      ##  TODO
      {:currency, false} ->
        {:error, "Cannot still create transaction multi-currency"}
    end
  end

  defp transaction_create(data) do
    case format_data(data) do
      {:ok, data} ->
        entries =
          for entry <- data.entries do
            struct!(Conta.Command.AccountTransaction.Entry, entry)
          end

        if :ok == Conta.Ledger.create_account_transaction(data.on_date, entries) do
          "Transaction created successfully"
        else
          "Error executing the commands"
        end

      {:error, message} ->
        message
    end
  end
end
