defmodule Conta.Automator.Lua do
  require Record

  Record.defrecordp(:luerl, Record.extract(:luerl, from_lib: "luerl/include/luerl.hrl"))

  defp process_data({:ok, [data], _state}), do: process_data(data, "")
  defp process_data({:ok, [], _state}), do: nil

  defp process_data({:error, [{_, _, {reason, _}}], _}), do: {:error, nil, reason}
  defp process_data({:error, [{_, _, reason}], _}), do: {:error, nil, reason}

  defp process_data({:lua_error, reason, state}) do
    {:current_line, line, _file} =
      List.keyfind(luerl(state, :cs), :current_line, 0) || {:current_line, nil, nil}

    {:error, line, reason}
  end

  defp process_data(data, key) do
    cond do
      is_integer(data) and String.ends_with?(key, "_price") ->
        Decimal.new(data) |> Decimal.div(100)

      not is_list(data) ->
        data

      Enum.all?(data, fn {k, _} -> is_integer(k) end) ->
        Enum.map(data, fn {_, value} -> process_data(value, "") end)

      :else ->
        Map.new(data, fn {k, v} -> {k, process_data(v, k)} end)
    end
  end

  def run(code, params) do
    # `set_table_keys_dec` handles translation of Erlang to Lua types automatically
    params
    |> Enum.reduce(:luerl.init(), fn {name, value}, state ->
      {:ok, new_state} = :luerl.set_table_keys_dec([name], value, state)
      new_state
    end)
    |> then(&:luerl.do_dec(code, &1))
    |> process_data()
    |> case do
      {:error, line, reason} ->
        line_info = if line, do: "line #{line} ", else: ""
        {:error, "#{line_info}error #{inspect(reason)}"}

      result ->
        {:ok, result}
    end
  end
end
