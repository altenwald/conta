defmodule ContaBot.Action.CandleTest do
  use Conta.DataCase, async: false
  import Conta.LedgerFixtures

  alias ContaBot.Action.Candle
  alias ExGram.Cnt
  alias ExGram.Model.{Chat, Message, Update, User}
  alias ExGram.Responses.Answer

  defmodule FakeBotApi do
    def send_photo(chat_id, photo, opts \\ []) do
      send(self(), {:bot_send_photo, chat_id, photo, opts})
      {:ok, %{message_id: 999}}
    end
  end

  setup do
    Application.put_env(:conta_bot, :bot_api, FakeBotApi)
    on_exit(fn -> Application.delete_env(:conta_bot, :bot_api) end)
    :ok
  end

  defp build_context(opts) do
    text = Keyword.get(opts, :text, "")
    chat_id = Keyword.get(opts, :chat_id, 12_345)

    %Cnt{
      name: :conta_bot,
      answers: [],
      extra: %{},
      update: %Update{
        update_id: 1,
        message: %Message{
          message_id: 1,
          chat: %Chat{id: chat_id, type: "private"},
          from: %User{id: 1, is_bot: false, first_name: "Test", username: "testuser"},
          date: 1_600_000_000,
          text: text
        }
      }
    }
  end

  defp build_callback_context(opts) do
    data = Keyword.get(opts, :data, "")
    chat_id = Keyword.get(opts, :chat_id, 12_345)

    %Cnt{
      name: :conta_bot,
      answers: [],
      extra: %{},
      update: %Update{
        update_id: 2,
        callback_query: %ExGram.Model.CallbackQuery{
          id: "cq_1",
          from: %User{id: 1, is_bot: false, first_name: "Test", username: "testuser"},
          message: %Message{
            message_id: 2,
            chat: %Chat{id: chat_id, type: "private"},
            date: 1_600_000_000,
            text: "Prompt"
          },
          data: data
        }
      }
    }
  end

  defp get_answers(%Cnt{answers: answers}) do
    Enum.map(answers, fn
      {:response, resp} -> resp
      other -> other
    end)
  end

  defp find_answer_with_text(context, expected_text) do
    Enum.find(get_answers(context), fn
      %Answer{text: text} -> text =~ expected_text
      _ -> false
    end)
  end

  defp find_answer_with_markup(context) do
    Enum.find(get_answers(context), fn
      %Answer{ops: ops} -> ops[:reply_markup] != nil
      _ -> false
    end)
  end

  describe "/candle initial command" do
    test "without arguments prompts user with account selector" do
      _asset = insert(:account, %{name: ~w[Assets], type: :assets, currency: :EUR})
      _bank = insert(:account, %{name: ~w[Assets Banks], type: :assets, currency: :EUR})

      context = build_context(text: "/candle")
      res = Candle.handle({:init, "candle"}, context)

      answer = find_answer_with_markup(res)
      assert answer != nil
      assert answer.text == "Choose an account for candle chart"
      assert %ExGram.Model.InlineKeyboardMarkup{} = answer.ops[:reply_markup]
    end

    test "with valid account generates candlestick chart and sends photo" do
      _asset = insert(:account, %{name: ~w[Assets], type: :assets, currency: :EUR})
      _checking = insert(:account, %{name: ~w[Assets Checking], type: :assets, currency: :EUR})

      context = build_context(text: "/candle Assets.Checking")
      Candle.handle({:init, "candle"}, context)

      assert_receive {:bot_send_photo, 12_345, {:file_content, png_binary, filename}, _opts}
      assert filename == "candle_Assets_Checking.png"
      assert is_binary(png_binary)
      assert String.starts_with?(png_binary, <<137, 80, 78, 71>>)
    end

    test "with valid account and custom months generates chart" do
      _asset = insert(:account, %{name: ~w[Assets], type: :assets, currency: :EUR})
      _checking = insert(:account, %{name: ~w[Assets Checking], type: :assets, currency: :EUR})

      context = build_context(text: "/candle Assets.Checking 6")
      Candle.handle({:init, "candle"}, context)

      assert_receive {:bot_send_photo, 12_345, {:file_content, png_binary, "candle_Assets_Checking.png"},
                      _opts}

      assert String.starts_with?(png_binary, <<137, 80, 78, 71>>)
    end

    test "with invalid months returns error message" do
      context = build_context(text: "/candle Assets.Checking invalid")
      res = Candle.handle({:init, "candle"}, context)

      answer = find_answer_with_text(res, "Invalid number of months")
      assert answer != nil
      refute_receive {:bot_send_photo, _, _, _}
    end

    test "with unknown account returns error message" do
      context = build_context(text: "/candle NonExistent.Account")
      res = Candle.handle({:init, "candle"}, context)

      answer = find_answer_with_text(res, "Account not found")
      assert answer != nil
      refute_receive {:bot_send_photo, _, _, _}
    end
  end

  describe "interactive flow callbacks" do
    test "drill-down callback displays subaccounts" do
      asset = insert(:account, %{name: ~w[Assets], type: :assets, currency: :EUR})
      _bank = insert(:account, %{name: ~w[Assets Banks], parent_id: asset.id, type: :assets, currency: :EUR})

      context = build_callback_context(data: "candle Assets")
      res = Candle.handle({:callback, "Assets"}, context)

      select_answer = find_answer_with_markup(res)
      assert select_answer != nil
      markup = select_answer.ops[:reply_markup]

      assert Enum.any?(markup.inline_keyboard, fn row ->
               Enum.any?(row, fn btn -> btn.text == "Assets.Banks" end)
             end)
    end

    test "account selection event prompts for time range" do
      _asset = insert(:account, %{name: ~w[Assets], type: :assets, currency: :EUR})
      _checking = insert(:account, %{name: ~w[Assets Checking], type: :assets, currency: :EUR})

      context = build_callback_context(data: "event candle Assets.Checking")
      res = Candle.handle({:event, "Assets.Checking"}, context)

      select_answer = find_answer_with_markup(res)
      assert select_answer != nil
      assert select_answer.text =~ "Choose time period for Assets.Checking"
      markup = select_answer.ops[:reply_markup]

      button_texts =
        markup.inline_keyboard
        |> List.flatten()
        |> Enum.map(& &1.text)

      assert "3 months" in button_texts
      assert "6 months" in button_texts
      assert "12 months (1 year)" in button_texts
      assert "24 months (2 years)" in button_texts
    end

    test "months callback generates chart and dispatches photo" do
      _asset = insert(:account, %{name: ~w[Assets], type: :assets, currency: :EUR})
      _checking = insert(:account, %{name: ~w[Assets Checking], type: :assets, currency: :EUR})

      context = build_callback_context(data: "candle months Assets.Checking 6")
      Candle.handle({:callback, "months Assets.Checking 6"}, context)

      assert_receive {:bot_send_photo, 12_345, {:file_content, png_binary, "candle_Assets_Checking.png"},
                      _opts}

      assert String.starts_with?(png_binary, <<137, 80, 78, 71>>)
    end
  end

  describe "direct text input" do
    test "parses account and months from text" do
      _asset = insert(:account, %{name: ~w[Assets], type: :assets, currency: :EUR})
      _checking = insert(:account, %{name: ~w[Assets Checking], type: :assets, currency: :EUR})

      context = build_context(text: "")
      Candle.handle({:text, "Assets.Checking 3"}, context)

      assert_receive {:bot_send_photo, 12_345, {:file_content, png_binary, "candle_Assets_Checking.png"},
                      _opts}

      assert String.starts_with?(png_binary, <<137, 80, 78, 71>>)
    end

    test "empty text returns hint" do
      context = build_context(text: "")
      res = Candle.handle({:text, ""}, context)

      answer = find_answer_with_text(res, "Please specify an account name")
      assert answer != nil
    end

    test "invalid months in text returns error" do
      context = build_context(text: "")
      res = Candle.handle({:text, "Assets.Checking zero"}, context)

      answer = find_answer_with_text(res, "Invalid number of months")
      assert answer != nil
    end
  end
end
