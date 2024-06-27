defmodule Conta.Automator.Excel do
  alias Elixlsx.Sheet
  alias Elixlsx.Workbook

  @unnamed "No name"

  defp col(0), do: ""

  defp col(i) when is_integer(i) do
    base = ?Z - ?A + 1
    unit = rem(i - 1, base)
    col(div(i - 1, base)) <> <<unit + ?A>>
  end

  def export([], filename), do: export(%{}, filename)

  def export([%{"name" => _, "rows" => _, "headers" => _}|_] = workbook, filename) do
    set_cell = fn {content, idx}, sheet, jdx ->
      Sheet.set_cell(sheet, "#{col(idx)}#{jdx}", to_str(content))
    end

    workbook
    |> Enum.reduce(%Workbook{}, fn %{"name" => name, "rows" => rows, "headers" => headers}, workbook ->
      sheet =
        headers
        |> Enum.with_index(1)
        |> Enum.reduce(Sheet.with_name(name), &set_cell.(&1, &2, 1))

      sheet =
        rows
        |> Enum.with_index(2)
        |> Enum.reduce(sheet, fn {row, i}, sheet ->
          row
          |> to_list()
          |> Enum.with_index(1)
          |> Enum.reduce(sheet, &set_cell.(&1, &2, i))
        end)

      Workbook.append_sheet(workbook, sheet)
    end)
    |> Elixlsx.write_to_memory(filename)
  end

  def export(sheet_data, filename) when is_list(sheet_data), do: export(%{@unnamed => sheet_data}, filename)

  def export(workbook, filename) when is_map(workbook) do
    workbook
    |> Enum.map(fn {sheet_name, [first_row|_] = sheet_data} ->
      headers = Map.keys(first_row)
      rows =
        for row <- sheet_data do
          row = if(is_struct(row), do: Map.from_struct(row), else: row)
          for head <- headers do
            row[head]
          end
        end

      %{"name" => sheet_name, "headers" => headers, "rows" => rows}
    end)
    |> export(filename)
  end

  defp to_str(atom) when is_atom(atom), do: to_string(atom)
  defp to_str(integer) when is_integer(integer), do: to_string(integer)
  defp to_str(float) when is_float(float), do: to_string(float)
  defp to_str(string) when is_binary(string), do: string
  defp to_str(date) when is_struct(date, Date), do: to_string(date)
  defp to_str(datetime) when is_struct(datetime, DateTime), do: to_string(datetime)
  defp to_str(datetime) when is_struct(datetime, NaiveDateTime), do: to_string(datetime)
  defp to_str(_otherwise), do: "(cannot convert)"

  defp to_list(struct) when is_struct(struct), do: to_list(Map.from_struct(struct))
  defp to_list(map) when is_map(map), do: Map.values(map)
  defp to_list(list) when is_list(list), do: list
end
