defmodule Conta.Automator.Lua do

  defp process_data({:ok, [data]}), do: process_data(data, "")

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
    params
    |> Enum.reduce(:luerl.init(), fn {name, value}, state ->
      :luerl.set_table([name], value, state)
    end)
    ### XXX: we have to use here charlist because binary breaks the collation.
    |> then(&:luerl.eval(to_charlist(code), &1))
    |> process_data()
    |> then(&{:ok, &1})
  end
end
