defmodule ContaBot.Action.Transaction.Worker do
  require Logger

  use GenStateMachine,
    callback_mode: :handle_event_function,
    restart: :transient

  @supervisor ContaBot.Action.Transaction.Workers
  @registry ContaBot.Action.Transaction.Registry

  @fields_to_take ~w[chat_id on_date description account_name relative_account_name amount]a

  defstruct chat_id: nil,
            on_date: nil,
            description: nil,
            account_name: nil,
            relative_account_name: nil,
            amount: nil,
            goto_confirm: false

  def start(opts) do
    DynamicSupervisor.start_child(@supervisor, {__MODULE__, opts})
  end

  defp via(chat_id) do
    {:via, Registry, {@registry, chat_id}}
  end

  def start_link(chat_id) do
    GenStateMachine.start_link(__MODULE__, [chat_id], name: via(chat_id))
  end

  def get_pid(chat_id) do
    case Registry.lookup(@registry, chat_id) do
      [{pid, _}] -> pid
      _ -> nil
    end
  end

  def exists?(chat_id), do: get_pid(chat_id) != nil

  def cast(chat_id, args), do: GenStateMachine.cast(via(chat_id), args)
  def call(chat_id, args), do: GenStateMachine.call(via(chat_id), args)

  def stop(chat_id) do
    if pid = get_pid(chat_id) do
      Process.monitor(pid)
      GenStateMachine.stop(via(chat_id))

      receive do
        {:DOWN, _ref, :process, _pid, _reason} -> :ok
      end
    else
      :ok
    end
  end

  def get_sticky(chat_id, key) do
    :persistent_term.get({__MODULE__, chat_id, key}, nil)
  end

  def put_sticky(chat_id, key, value) do
    :persistent_term.put({__MODULE__, chat_id, key}, value)
  end

  def init([chat_id]) do
    {:ok, :account_name, %__MODULE__{chat_id: chat_id}}
  end

  def handle_event({:call, from}, :get_data, state, data) do
    actions = [{:reply, from, {:ok, state, Map.take(data, @fields_to_take)}}]
    {:keep_state_and_data, actions}
  end

  def handle_event({:call, from}, {:callback, account}, :account_name, state_data) do
    actions = [{:reply, from, {:ok, {:account_name, account}}}]
    {:keep_state, %__MODULE__{state_data | account_name: account}, actions}
  end

  def handle_event({:call, from}, {:event, "description"}, :account_name, state_data) do
    state_data =
      if state_data.account_name do
        state_data
      else
        %__MODULE__{state_data | account_name: get_sticky(state_data.chat_id, :account_name)}
      end

    if state_data.goto_confirm do
      actions = [{:reply, from, {:ok, {:confirm, Map.take(state_data, @fields_to_take)}}}]
      {:next_state, :confirm, %__MODULE__{state_data | goto_confirm: false}, actions}
    else
      actions = [{:reply, from, {:ok, :description}}]
      {:next_state, :description, state_data, actions}
    end
  end

  def handle_event({:call, from}, {:event_sticky, "description"}, :account_name, state_data) do
    put_sticky(state_data.chat_id, :account_name, state_data.account_name)

    if state_data.goto_confirm do
      actions = [{:reply, from, {:ok, {:confirm, Map.take(state_data, @fields_to_take)}}}]
      {:next_state, :confirm, %__MODULE__{state_data | goto_confirm: false}, actions}
    else
      actions = [{:reply, from, {:ok, :description}}]
      {:next_state, :description, state_data, actions}
    end
  end

  def handle_event({:call, from}, {:text, description}, :description, state_data) do
    state_data = %__MODULE__{state_data | description: String.trim(description)}

    if state_data.goto_confirm do
      actions = [{:reply, from, {:ok, {:confirm, Map.take(state_data, @fields_to_take)}}}]
      {:next_state, :confirm, %__MODULE__{state_data | goto_confirm: false}, actions}
    else
      actions = [{:reply, from, {:ok, :relative_account_name}}]
      {:next_state, :relative_account_name, state_data, actions}
    end
  end

  def handle_event({:call, from}, {:callback, account}, :relative_account_name, state_data) do
    actions = [{:reply, from, {:ok, {:relative_account_name, account}}}]
    {:keep_state, %__MODULE__{state_data | relative_account_name: account}, actions}
  end

  def handle_event({:call, from}, {:event, "amount"}, :relative_account_name, state_data) do
    state_data =
      if state_data.relative_account_name do
        state_data
      else
        %__MODULE__{
          state_data
          | relative_account_name: get_sticky(state_data.chat_id, :relative_account_name)
        }
      end

    if state_data.goto_confirm do
      actions = [{:reply, from, {:ok, {:confirm, Map.take(state_data, @fields_to_take)}}}]
      {:next_state, :confirm, %__MODULE__{state_data | goto_confirm: false}, actions}
    else
      actions = [{:reply, from, {:ok, :amount}}]
      {:next_state, :amount, state_data, actions}
    end
  end

  def handle_event({:call, from}, {:event_sticky, "amount"}, :relative_account_name, state_data) do
    put_sticky(state_data.chat_id, :relative_account_name, state_data.relative_account_name)

    if state_data.goto_confirm do
      actions = [{:reply, from, {:ok, {:confirm, Map.take(state_data, @fields_to_take)}}}]
      {:next_state, :confirm, %__MODULE__{state_data | goto_confirm: false}, actions}
    else
      actions = [{:reply, from, {:ok, :amount}}]
      {:next_state, :amount, state_data, actions}
    end
  end

  def handle_event({:call, from}, {:text, amount}, :amount, state_data) do
    case ContaBot.Components.get_money(amount) do
      {:ok, amount} ->
        state_data = %__MODULE__{state_data | amount: amount}

        if state_data.goto_confirm do
          actions = [{:reply, from, {:ok, {:confirm, Map.take(state_data, @fields_to_take)}}}]
          {:next_state, :confirm, %__MODULE__{state_data | goto_confirm: false}, actions}
        else
          actions = [{:reply, from, {:ok, :on_date}}]
          {:next_state, :on_date, state_data, actions}
        end

      {:error, _} = error ->
        {:keep_state_and_data, [{:reply, from, error}]}
    end
  end

  def handle_event({:call, from}, {:callback, "on_date " <> on_date}, :on_date, _state_data) do
    {:keep_state_and_data, [{:next_event, {:call, from}, {:text, on_date}}]}
  end

  def handle_event({:call, from}, {:text, on_date}, :on_date, state_data) do
    case Date.from_iso8601(on_date) do
      {:ok, on_date} ->
        put_sticky(state_data.chat_id, :on_date, on_date)
        state_data = %__MODULE__{state_data | on_date: on_date}
        actions = [{:reply, from, {:ok, {:confirm, Map.take(state_data, @fields_to_take)}}}]
        {:next_state, :confirm, state_data, actions}

      {:error, _} ->
        {:keep_state_and_data, [{:reply, from, {:error, :invalid_date}}]}
    end
  end

  def handle_event({:call, from}, {:callback, "account_name"}, :confirm, state_data) do
    actions = [{:reply, from, {:ok, :account_name}}]
    state_data = %__MODULE__{state_data | goto_confirm: true}
    {:next_state, :account_name, state_data, actions}
  end

  def handle_event({:call, from}, {:callback, "description"}, :confirm, state_data) do
    actions = [{:reply, from, {:ok, :description}}]
    state_data = %__MODULE__{state_data | goto_confirm: true}
    {:next_state, :description, state_data, actions}
  end

  def handle_event({:call, from}, {:callback, "relative_account_name"}, :confirm, state_data) do
    actions = [{:reply, from, {:ok, :relative_account_name}}]
    state_data = %__MODULE__{state_data | goto_confirm: true}
    {:next_state, :relative_account_name, state_data, actions}
  end

  def handle_event({:call, from}, {:callback, "amount"}, :confirm, state_data) do
    actions = [{:reply, from, {:ok, :amount}}]
    state_data = %__MODULE__{state_data | goto_confirm: true}
    {:next_state, :amount, state_data, actions}
  end

  def handle_event({:call, from}, {:callback, "on_date"}, :confirm, state_data) do
    actions = [{:reply, from, {:ok, :on_date}}]
    state_data = %__MODULE__{state_data | goto_confirm: true}
    {:next_state, :on_date, state_data, actions}
  end

  def handle_event({:call, from}, {:callback, "confirm"}, :confirm, state_data) do
    actions = [
      {:reply, from, {:ok, Map.take(state_data, @fields_to_take)}},
      {:state_timeout, 10_000, :stop}
    ]

    {:next_state, :done, state_data, actions}
  end

  def handle_event({:call, from}, event, state, _data) do
    Logger.warning("invalid event #{state}: #{inspect(event)}")
    actions = [{:reply, from, {:error, :invalid_event}}]
    {:keep_state_and_data, actions}
  end

  def handle_event(:state_timeout, :stop, _state, data) do
    Logger.notice("stopping transaction for #{data.chat_id}")
    :stop
  end
end
