defmodule ContaBot.Components do
  import ExGram.Dsl
  import ContaBot.Action, only: [put_following_text: 1]
  alias ExGram.Model.InlineKeyboardButton
  alias ExGram.Model.InlineKeyboardMarkup
  require Logger

  def get_currency(text) do
    currencies = Conta.Ledger.list_used_currencies()

    if match = Regex.run(~r/([A-Z]{3})/, text, capture: :all_but_first) do
      try do
        currency = String.to_existing_atom(hd(match))
        if currency in currencies, do: currency
      rescue
        ArgumentError ->
          Logger.error("non existing atom #{hd(match)}")
          nil
      end
    end
  end

  def get_money(amount) do
    case Regex.run(~r/^(-?)([0-9]+)(?:\.([0-9]{1,2}))?$/, amount, capture: :all_but_first) do
      [sign, int | decimal] ->
        decimal =
          case decimal do
            [] ->
              0

            [decimal] when byte_size(decimal) == 1 ->
              String.to_integer(decimal) * 10

            [decimal] when byte_size(decimal) == 2 ->
              String.to_integer(decimal)
          end

        amount = String.to_integer(int) * 100 + decimal
        sign = if(sign == "-", do: -1, else: 1)
        {:ok, amount * sign}

      nil ->
        {:error, :invalid_amount}
    end
  end

  def get_chat_id(context) do
    cond do
      context.update.message ->
        context.update.message.chat.id

      context.update.callback_query ->
        context.update.callback_query.message.chat.id
    end
  end

  def answer_select(context, prompt, options, extra_options \\ [], opts \\ []) do
    extra_buttons =
      for {label, value} <- extra_options do
        %InlineKeyboardButton{text: label, callback_data: value}
      end

    buttons =
      if Enum.all?(options, &is_tuple/1) do
        for {label, value} <- options do
          [%InlineKeyboardButton{text: label, callback_data: value}]
        end
      else
        Enum.map(options, fn
          {label, value} ->
            [%InlineKeyboardButton{text: label, callback_data: value}]

          sub_options when is_list(sub_options) ->
            for {label, value} <- sub_options do
              %InlineKeyboardButton{text: label, callback_data: value}
            end
        end)
      end ++ [extra_buttons]

    markup = %InlineKeyboardMarkup{inline_keyboard: buttons}
    answer(context, prompt, [{:reply_markup, markup} | opts])
  end

  def escape_markdown(text) do
    Regex.replace(~r/([_*~`#+=|\{\}!\[\].\-\(\)])/, text, "\\\\\\1", global: true)
  end

  def answer_me(context, name, prompt, opts \\ []) do
    put_following_text(name)
    answer(context, prompt, opts)
  end

  def delete_callback(context) do
    delete(context, context.update.callback_query.message)
  end

  def choose_date(context, action) do
    put_following_text(action)

    answer_select(
      context,
      "Write or choose date for the entry (YYYY-MM-DD)",
      [
        {"Today", "#{action} date #{Date.utc_today()}"},
        {"Yesterday", "#{action} date #{Date.add(Date.utc_today(), -1)}"}
      ]
    )
  end

  def choose_account(context, name, prompt, sticky, next, parent \\ nil)

  def choose_account(context, name, prompt, sticky, next, parent) when is_binary(parent) do
    choose_account(context, name, prompt, sticky, next, String.split(parent, "."))
  end

  def choose_account(context, name, prompt, sticky, next, nil) do
    options =
      Conta.Ledger.list_accounts_by_parent(nil)
      |> Enum.map(&Enum.join(&1.name, "."))
      |> Enum.map(&{&1, "#{name} #{&1}"})

    extra =
      if sticky do
        [{"Continue with #{sticky}...", "event " <> next}]
      else
        []
      end

    answer_select(context, prompt, options, extra)
  end

  def choose_account(context, name, prompt, sticky, next, parent) when is_list(parent) do
    options =
      Conta.Ledger.list_accounts_by_parent(parent)
      |> Enum.map(&Enum.join(&1.name, "."))
      |> Enum.map(&{&1, "#{name} #{&1}"})

    extra = [
      {"Continue with #{Enum.join(parent, ".")}...", "event " <> next},
      if(sticky !== false,
        do: {"Stick with #{Enum.join(parent, ".")}...", "event sticky " <> next}
      )
    ]

    context
    |> delete_callback()
    |> answer_select(prompt, options, extra)
  end

  def account_fmt(account_name) do
    (account_name || "-- Breakdown")
    |> Enum.join(".")
    |> escape_markdown()
  end

  def currency_fmt(value) do
    value
    |> to_string()
    |> String.pad_leading(15)
    |> escape_markdown()
  end

  def month_year_fmt(month, year) do
    "#{year}/#{String.pad_leading(to_string(month), 2, "0")}"
  end
end
