defmodule ContaBot.Action.Candle do
  @moduledoc """
  Bot action to generate and send candlestick charts for account monthly balance overviews.
  """
  use ContaBot.Action
  require Logger

  @default_months 12

  defp bot_api do
    Application.get_env(:conta_bot, :bot_api, ExGram)
  end

  @impl ContaBot.Action
  def handle({:init, "candle"}, context) do
    case extract_args(context) do
      [] ->
        choose_account(context, "candle", "Choose an account for candle chart", false, "")

      [account] ->
        render_and_send(account, @default_months, context)

      [account, months_str | _] ->
        case Integer.parse(months_str) do
          {months, ""} when months > 0 ->
            render_and_send(account, months, context)

          _ ->
            answer(context, "Invalid number of months: #{months_str}")
        end
    end
  end

  def handle({:callback, "months " <> data}, context) do
    case String.split(data, " ", parts: 2) do
      [account, months_str] ->
        case Integer.parse(months_str) do
          {months, ""} when months > 0 ->
            context
            |> delete_callback()
            |> then(&render_and_send(account, months, &1))

          _ ->
            answer(context, "Invalid number of months")
        end

      _ ->
        answer(context, "Invalid selection")
    end
  end

  def handle({:callback, account}, context) do
    choose_account(
      context,
      "candle",
      "Choose an account for candle chart",
      false,
      "candle #{account}",
      account
    )
  end

  def handle({:event, account}, context) do
    options = [
      {"3 months", "candle months #{account} 3"},
      {"6 months", "candle months #{account} 6"},
      {"12 months (1 year)", "candle months #{account} 12"},
      {"24 months (2 years)", "candle months #{account} 24"}
    ]

    context
    |> delete_callback()
    |> answer_select("Choose time period for #{account} (default 12 months):", options)
  end

  def handle({:text, text}, context) do
    case String.split(text, ~r/\s+/, trim: true) do
      [] ->
        answer(context, "Please specify an account name")

      [account] ->
        render_and_send(account, @default_months, context)

      [account, months_str | _] ->
        case Integer.parse(months_str) do
          {months, ""} when months > 0 ->
            render_and_send(account, months, context)

          _ ->
            answer(context, "Invalid number of months: #{months_str}")
        end
    end
  end

  defp extract_args(context) do
    text =
      cond do
        is_map(context.extra) and is_map(context.extra[:params]) and
            is_binary(context.extra[:params].text) ->
          context.extra[:params].text

        context.update && context.update.message && is_binary(context.update.message.text) ->
          Regex.replace(~r{^/candle(?:@\w+)?\s*}, context.update.message.text, "")

        true ->
          ""
      end

    String.split(text, ~r/\s+/, trim: true)
  end

  defp render_and_send(account_param, months, context) do
    case Conta.Stats.get_account(account_param) do
      {:ok, account} ->
        chart = Conta.Stats.chart_account(account, months)
        account_name_str = Enum.join(account.name, ".")
        slug = String.replace(account_name_str, ".", "_")
        filename = "candle_#{slug}.png"

        case Plotto.to_png(chart) do
          {:ok, image} ->
            chat_id = get_chat_id(context)
            bot_api().send_photo(chat_id, {:file_content, image, filename})
            context

          {:error, reason} ->
            Logger.error("Failed to render candle chart PNG: #{inspect(reason)}")
            answer(context, "Error trying to create the image")
        end

      {:error, _reason} ->
        answer(context, "Account not found: #{account_param}")
    end
  end
end
