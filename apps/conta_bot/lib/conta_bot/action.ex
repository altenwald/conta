defmodule ContaBot.Action do
  use ExGram.Bot, name: :conta_bot, setup_commands: true
  require Logger
  alias ContaBot.Action.Users

  command("graph", description: "Receive a graph for specific data")
  command("income", description: "Get income for last 6 months")
  command("invoice", description: "List invoices")
  command("outcome", description: "Get outcome for last 6 months")
  command("patrimony", description: "Get Patrimony for last 6 months")
  command("pnl", description: "Get Profits & Losses for last 6 months")
  command("search", description: "Search entries based on description and account name")
  command("shortcut", description: "Run a shortcut code written in Lua/PHP")
  command("statement", description: "Last entries for a selected account")
  command("status", description: "Status of the assets")
  command("transaction", description: "Add account transaction")

  defmacro __using__(_opts) do
    quote do
      import ExGram.Dsl
      import ContaBot.Components, except: [answer_me: 3, answer_me: 4]

      import ContaBot.Action,
        only: [
          put_following_text: 1,
          take_following_text: 0
        ]

      @behaviour ContaBot.Action

      def name do
        Macro.underscore(__MODULE__) |> String.split("/") |> List.last()
      end

      def answer_me(context, prompt, opts \\ []) do
        ContaBot.Components.answer_me(context, name(), prompt, opts)
      end

      def match_me(regex) do
        ContaBot.Action.match_me(__MODULE__, regex)
      end
    end
  end

  @type event() ::
          {:init, String.t()}
          | {:event_sticky, String.t()}
          | {:event, String.t()}
          | {:callback, String.t()}
          | {:text, String.t()}

  @callback handle(event(), ExGram.Cnt.t()) :: ExGram.Cnt.t()

  def handle({:command, command, params}, context) do
    if Users.granted_user?(params.from.username) do
      command = to_string(command)
      handle({:init, command}, command, context)
    else
      answer(context, "You're not allowed to ask me anything. Sorry.")
    end
  end

  def handle({:callback_query, %{data: "event sticky " <> data}}, context) do
    [name, data] = String.split(data, " ", parts: 2)
    handle({:event_sticky, data}, name, context)
  end

  def handle({:callback_query, %{data: "event " <> data}}, context) do
    [name, data] = String.split(data, " ", parts: 2)
    handle({:event, data}, name, context)
  end

  def handle({:callback_query, %{data: data}}, context) do
    [name, data] = String.split(data, " ", parts: 2)
    handle({:callback, data}, name, context)
  end

  def handle({:text, text, _metadata}, context) do
    following = take_following_text()

    cond do
      is_nil(following) ->
        Logger.debug("ignored text: #{text}")

      is_binary(following) ->
        handle({:text, text}, following, context)
    end
  end

  def handle(request, context) do
    Logger.notice("received: #{inspect(request)}")
    context
  end

  defp handle(event, following, context) do
    module = Module.concat(__MODULE__, Macro.camelize(following))
    Code.ensure_loaded(module)
    Logger.debug("requested command #{inspect(following)} - trying #{module}")

    cond do
      function_exported?(module, :handle, 2) ->
        module.handle(event, context)

      module = get_match_module(following) ->
        module.handle(event, context)

      :else ->
        answer(context, "Command not found. Sorry.")
    end
  end

  def match_me(module, regex) do
    key = {__MODULE__, :match_me}
    matches = :persistent_term.get(key, nil) || %{}
    :persistent_term.put(key, Map.update(matches, module, [regex], &[regex | &1]))
  end

  def get_match_module(command) do
    key = {__MODULE__, :match_me}
    matches = :persistent_term.get(key, nil) || %{}

    f = fn {_module, regex_expressions} ->
      Enum.any?(regex_expressions, &Regex.match?(&1, command))
    end

    if match = Enum.find(matches, f) do
      {module, _regex} = match
      module
    end
  end

  def put_following_text(action) do
    :persistent_term.put({__MODULE__, :following_text}, action)
  end

  def take_following_text do
    key = {__MODULE__, :following_text}

    if following = :persistent_term.get(key, nil) do
      :persistent_term.erase(key)
      following
    end
  end
end
