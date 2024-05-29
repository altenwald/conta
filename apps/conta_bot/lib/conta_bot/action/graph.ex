defmodule ContaBot.Action.Graph do
  use ContaBot.Action
  require Logger

  @impl ContaBot.Action
  def handle({:init, _command}, context) do
    options = [
      {"Patrimony", "graph patrimony"},
      {"Income", "graph income"},
      {"Outcome", "graph outcome"},
      {"Profits & Losses", "graph pnl"}
    ]

    answer_select(context, "What kind of graphic do you want to get?", options)
  end

  def handle({:callback, "patrimony"}, context) do
    options =
      for currency <- Conta.Ledger.list_used_currencies() do
        name = Money.Currency.name(currency)
        symbol = Money.Currency.symbol(currency)
        {"#{name} (#{symbol})", "graph patrimony #{currency}"}
      end

    context
    |> delete_callback()
    |> answer_select("What patrimony currency do you want to see?", options)
  end

  def handle({:callback, "outcome"}, context) do
    options =
      for currency <- Conta.Ledger.list_used_currencies() do
        name = Money.Currency.name(currency)
        symbol = Money.Currency.symbol(currency)
        {"#{name} (#{symbol})", "graph outcome #{currency}"}
      end

    context
    |> delete_callback()
    |> answer_select("What outcome currency do you want to see?", options)
  end

  def handle({:callback, "income"}, context) do
    options =
      for currency <- Conta.Ledger.list_used_currencies() do
        name = Money.Currency.name(currency)
        symbol = Money.Currency.symbol(currency)
        {"#{name} (#{symbol})", "graph income #{currency}"}
      end

    context
    |> delete_callback()
    |> answer_select("What income currency do you want to see?", options)
  end

  def handle({:callback, "pnl"}, context) do
    options =
      for currency <- Conta.Ledger.list_used_currencies() do
        name = Money.Currency.name(currency)
        symbol = Money.Currency.symbol(currency)
        {"#{name} (#{symbol})", "graph pnl #{currency}"}
      end

    context
    |> delete_callback()
    |> answer_select("What profits & losses currency do you want to see?", options)
  end

  def handle({:callback, "patrimony " <> currency}, context) do
    graph =
      currency
      |> get_currency()
      |> Conta.Stats.graph_patrimony()
      |> to_string()

    case Resvg.svg_string_to_png_buffer(graph, resources_dir: "/tmp") do
      {:ok, image} ->
        ExGram.send_photo(get_chat_id(context), {:file_content, image, "patrimony.png"})
        delete(context, context.update.callback_query.message)

      {:error, reason} ->
        Logger.error("trying to create image wrong! #{inspect(reason)}")
        answer(context, "Error trying to create the image")
    end
  end

  def handle({:callback, "outcome " <> currency}, context) do
    graph =
      currency
      |> get_currency()
      |> Conta.Stats.graph_outcome()
      |> to_string()

    case Resvg.svg_string_to_png_buffer(graph, resources_dir: "/tmp") do
      {:ok, image} ->
        ExGram.send_photo(get_chat_id(context), {:file_content, image, "outcome.png"})
        delete(context, context.update.callback_query.message)

      {:error, reason} ->
        Logger.error("trying to create image wrong! #{inspect(reason)}")
        answer(context, "Error trying to create the image")
    end
  end

  def handle({:callback, "income " <> currency}, context) do
    graph =
      currency
      |> get_currency()
      |> Conta.Stats.graph_income()
      |> to_string()

    case Resvg.svg_string_to_png_buffer(graph, resources_dir: "/tmp") do
      {:ok, image} ->
        ExGram.send_photo(get_chat_id(context), {:file_content, image, "income.png"})
        delete(context, context.update.callback_query.message)

      {:error, reason} ->
        Logger.error("trying to create image wrong! #{inspect(reason)}")
        answer(context, "Error trying to create the image")
    end
  end

  def handle({:callback, "pnl " <> currency}, context) do
    graph =
      currency
      |> get_currency()
      |> Conta.Stats.graph_pnl(6)
      |> to_string()

    case Resvg.svg_string_to_png_buffer(graph, resources_dir: "/tmp") do
      {:ok, image} ->
        ExGram.send_photo(get_chat_id(context), {:file_content, image, "pnl.png"})
        delete(context, context.update.callback_query.message)

      {:error, reason} ->
        Logger.error("trying to create image wrong! #{inspect(reason)}")
        answer(context, "Error trying to create the image")
    end
  end
end
