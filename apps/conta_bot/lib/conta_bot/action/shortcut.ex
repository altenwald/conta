defmodule ContaBot.Action.Shortcut do
  use ContaBot.Action
  require Logger

  @impl ContaBot.Action
  def handle(:init, context) do
    options =
      for shortcut <- Conta.Ledger.list_shortcuts() do
        [
          {"run #{shortcut.name}", "shortcut init #{shortcut.name}"},
          {"view #{shortcut.name}", "shortcut view #{shortcut.name}"}
        ]
      end

    extra = [{"Cancel", "shortcut cancel"}]
    answer_select(context, "Choose a shortcut", options, extra)
  end

  def handle({:callback, "cancel"}, context) do
    delete_callback(context)
  end

  def handle({:callback, "view " <> shortcut}, context) do
    if shortcut = Conta.Ledger.get_shortcut(shortcut) do
      output = """
      ```#{shortcut.language}
      #{escape_markdown(shortcut.code)}
      ```
      """

      answer(context, output, parse_mode: "MarkdownV2")
    else
      context
      |> delete_callback()
      |> answer("Shortcut [#{shortcut}] doesn't exist")
    end
  end

  def handle({:callback, "init " <> shortcut}, context) do
    if shortcut = Conta.Ledger.get_shortcut(shortcut) do
      context
      |> store_init(shortcut.name, shortcut.params)
      |> delete_callback()
      |> show_next_input()
    else
      context
      |> delete_callback()
      |> answer("Shortcut [#{shortcut}] doesn't exist")
    end
  end

  def handle({:callback, "date " <> date}, context) do
    case store_get_next_param(context) do
      %_{type: :date, name: name} ->
        context
        |> store_put_param(name, date)
        |> show_next_input()

      _ ->
        context
        |> delete_callback()
        |> answer("An error occurred, we weren't waiting for a date")
    end
  end

  def handle({:callback, "option " <> option}, context) do
    case store_get_next_param(context) do
      %_{type: :options, name: name} ->
        context
        |> store_put_param(name, option)
        |> show_next_input()

      _ ->
        context
        |> delete_callback()
        |> answer("An error occurred, we weren't waiting for an option")
    end
  end

  def handle({:event, "next_account_name " <> account}, context) do
    case store_get_next_param(context) do
      %_{type: :account_name, name: name} ->
        account = String.split(account, ".")

        context
        |> store_put_param(name, account)
        |> show_next_input()

      _ ->
        context
        |> delete_callback()
        |> answer("An error occurred, we weren't waiting for an account")
    end
  end

  def handle({:callback, "account_name " <> account}, context) do
    context
    |> delete_callback()
    |> choose_account(
      "shortcut account_name",
      "Choose the account name",
      false,
      "shortcut next_account_name #{account}",
      account
    )
  end

  def handle({:text, input}, context) do
    context
    |> store_get_next_param()
    |> handle_by_type(input, context)
  end

  def handle_by_type(%_{type: :string, name: name}, input, context) do
    context
    |> store_put_param(name, input)
    |> show_next_input()
  end

  def handle_by_type(%_{type: :money, name: name}, input, context) do
    case get_money(input) do
      {:ok, money} ->
        context
        |> store_put_param(name, money)
        |> show_next_input()

      {:error, _} ->
        context
        |> answer("Invalid money value")
        |> show_next_input()
    end
  end

  def handle_by_type(%_{type: :date, name: name}, input, context) do
    if Date.from_iso8601(input) do
      context
      |> store_put_param(name, input)
      |> show_next_input()
    else
      context
      |> answer("Invalid date")
      |> show_next_input()
    end
  end

  def handle_by_type(%_{type: :integer, name: name}, input, context) do
    case Integer.parse(input) do
      {number, ""} ->
        context
        |> store_put_param(name, number)
        |> show_next_input()

      _ ->
        context
        |> answer("Invalid number")
        |> show_next_input()
    end
  end

  def handle_by_type(%_{type: :float, name: name}, input, context) do
    case Float.parse(input) do
      {number, ""} ->
        context
        |> store_put_param(name, number)
        |> show_next_input()

      _ ->
        context
        |> answer("Invalid number")
        |> show_next_input()
    end
  end

  defp run_shortcut(context) do
    name = get_shortcut_name(context)
    params = store_get_params(context)

    case Conta.Ledger.run_shortcut(name, params) do
      :ok ->
        answer(context, "Shortcut executed successfully")

      {:error, error} ->
        answer(context, "An error happened: #{inspect(error)}")
    end
  end

  defp show_next_input(context) do
    context
    |> store_get_next_param()
    |> show_next_input_by_type(context)
  end

  defp show_next_input_by_type(%_{type: :string, name: name}, context),
    do: answer_me(context, "write the content for: #{name}")

  defp show_next_input_by_type(%_{type: :integer, name: name}, context),
    do: answer_me(context, "write a number for: #{name}")

  defp show_next_input_by_type(%_{type: :float, name: name}, context),
    do: answer_me(context, "write a float number for: #{name}")

  defp show_next_input_by_type(%_{type: :money, name: name}, context),
    do: answer_me(context, "write the money value with a dot (.) and two decimals for: #{name}")

  defp show_next_input_by_type(%_{type: :options, name: name, options: options}, context) do
    options = Enum.map(options, &{&1, "shortcut option #{&1}"})
    extra = [{"Cancel", "shortcut cancel"}]
    answer_select(context, "choose an option for #{name}", options, extra)
  end

  defp show_next_input_by_type(%_{type: :account_name}, context) do
    choose_account(
      context,
      "shortcut account_name",
      "Choose the account name",
      false,
      "shortcut next"
    )
  end

  defp show_next_input_by_type(%_{type: :date}, context), do: choose_date(context, "shortcut")

  defp show_next_input_by_type(%_{type: :currency, name: name}, context) do
    options = Enum.map(Conta.Ledger.list_used_currencies(), &{&1, "shortcut option #{&1}"})
    extra = [{"Cancel", "shortcut cancel"}]
    answer_select(context, "choose a currency for #{name}", options, extra)
  end

  defp show_next_input_by_type(nil, context), do: run_shortcut(context)

  defp store_init(context, name, params) do
    chat_id = get_chat_id(context)
    params = Enum.to_list(params)
    :persistent_term.put({__MODULE__, chat_id, :shortcut}, name)
    :persistent_term.put({__MODULE__, chat_id, :params}, params)
    :persistent_term.put({__MODULE__, chat_id, :data}, %{})
    context
  end

  defp get_shortcut_name(context) do
    chat_id = get_chat_id(context)
    :persistent_term.get({__MODULE__, chat_id, :shortcut})
  end

  defp store_get_next_param(context) do
    chat_id = get_chat_id(context)

    case :persistent_term.get({__MODULE__, chat_id, :params}) do
      [next | _] -> next
      [] -> nil
    end
  end

  defp store_put_param(context, key, value) do
    chat_id = get_chat_id(context)

    case :persistent_term.get({__MODULE__, chat_id, :params}) do
      [%_{name: ^key} | params] ->
        :persistent_term.put({__MODULE__, chat_id, :params}, params)
        data = :persistent_term.get({__MODULE__, chat_id, :data})
        data = Map.put(data, key, value)
        :persistent_term.put({__MODULE__, chat_id, :data}, data)
        context

      other ->
        Logger.error("expected #{key} but we have #{inspect(other)}")
        {:error, :wrong_param}
    end
  end

  defp store_get_params(context) do
    chat_id = get_chat_id(context)
    :persistent_term.get({__MODULE__, chat_id, :data})
  end
end
