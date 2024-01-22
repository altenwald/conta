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

  defp transaction_create(data) do
    Logger.debug("creating transaction for data: #{inspect(data)}")
    account_name = String.split(data.account_name, ".")
    relative_account_name = String.split(data.relative_account_name, ".")

    with {:ok, account} <- Conta.Ledger.get_account_by_name(account_name),
         {:ok, relative_account} <- Conta.Ledger.get_account_by_name(relative_account_name),
         {:currency, true} <- {:currency, account.currency == relative_account.currency} do
      {add_account, add_relative_account} =
        if (account.type in ~w[assets expenses]a and data.amount > 0) or data.amount < 0 do
          {
            &Map.merge(&1, %{debit: data.amount, credit: 0}),
            &Map.merge(&1, %{credit: data.amount, debit: 0})
          }
        else
          {
            &Map.merge(&1, %{credit: -data.amount, debit: 0}),
            &Map.merge(&1, %{debit: -data.amount, credit: 0})
          }
        end

      entries = [
        add_account.(%Conta.Command.AccountTransaction.Entry{
          description: data.description,
          account_name: account_name,
          change_currency: relative_account.currency
        }),
        add_relative_account.(%Conta.Command.AccountTransaction.Entry{
          description: data.description,
          account_name: relative_account_name,
          change_currency: account.currency
        })
      ]

      if :ok == Conta.create_transaction(data.on_date, entries) do
        "Transaction created successfully"
      else
        "Error executing the commands"
      end
    else
      {:error, _} -> "Account doesn't exist"
      ##  TODO
      {:currency, false} -> "Cannot still create transaction multi-currency"
    end
  end
end
