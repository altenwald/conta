defmodule Conta.Automator.Lua do
  require Record

  Record.defrecordp(:luerl, Record.extract(:luerl, from_lib: "luerl/include/luerl.hrl"))

  defp process_data({:ok, [data], state}) do
    state
    |> Luerl.decode(data)
    |> process_data("")
  end

  defp process_data({:lua_error, reason, state}) do
    {:current_line, line, _file} = List.keyfind(luerl(state, :cs), :current_line, 0)
    {:error, line, reason}
  end

  defp process_data(data, key) do
    cond do
      is_integer(data) and String.ends_with?(key, "_price") ->
        data
        |> Decimal.new()
        |> Decimal.div(100)

      not is_list(data) ->
        data

      Enum.all?(data, fn {k, _} -> is_integer(k) end) ->
        data
        |> Enum.sort()
        |> Enum.map(fn {_, value} -> process_data(value, "") end)

      :else ->
        Map.new(data, fn {k, v} -> {k, process_data(v, k)} end)
    end
  end

  def run(code, params) do
    params
    |> Enum.reduce(Luerl.init(), fn {name, value}, state ->
      {:ok, state} = Luerl.set_table_keys(state, [name], value)
      state
    end)
    ### XXX: we have to use here charlist because binary breaks the collation.
    |> Luerl.do(to_charlist(code))
    |> process_data()
    |> case do
      {:error, line, reason} -> {:error, "line #{line} error #{inspect(reason)}"}
      result -> {:ok, result}
    end
  end
end
