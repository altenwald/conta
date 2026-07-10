defmodule Conta.Automator.Lua do
  require Record

  Record.defrecordp(:luerl, Record.extract(:luerl, from_lib: "luerl/include/luerl.hrl"))

  defp process_data({:ok, [data], _state}), do: process_data(data, "")
  defp process_data({:ok, [], _state}), do: :no_return

  defp process_data({:error, errors, _warnings}) when is_list(errors) do
    message = errors |> Enum.map(&format_compile_error/1) |> Enum.join("; ")
    {:error, message}
  end

  defp process_data({:lua_error, reason, state}) do
    {:current_line, line, _file} =
      List.keyfind(luerl(state, :cs), :current_line, 0) || {:current_line, nil, nil}

    message = format_runtime_error(reason)
    {:error, if(line, do: "line #{line}: #{message}", else: message)}
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

  defp format_compile_error({line, module, reason}) do
    "line #{line}: #{iodata_to_string(module.format_error(reason))}"
  rescue
    _ -> "line #{line}: #{inspect(reason)}"
  end

  defp format_runtime_error(reason) do
    iodata_to_string(:luerl_lib.format_error(reason))
  rescue
    _ -> inspect(reason)
  end

  defp iodata_to_string(iodata), do: IO.iodata_to_binary(iodata)

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
      {:error, message} ->
        {:error, message}

      :no_return ->
        {:error, "the script finished without returning a value (missing a `return` statement?)"}

      result ->
        {:ok, result}
    end
  end
end
