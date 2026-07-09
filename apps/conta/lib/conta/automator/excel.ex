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

  def export(data, filename) do
    data
    |> shape_sheets()
    |> build_workbook()
    |> Elixlsx.write_to_memory(filename)
  end

  @doc """
  Normalizes any of the shapes accepted by `export/2` into a plain list of
  `%{"name" => _, "headers" => _, "rows" => _}` sheets, without writing an
  actual workbook. Returns `:error` (instead of raising) for any other shape,
  since the input comes from an arbitrary Lua script's return value.
  """
  @spec to_sheets(term()) :: {:ok, [map()]} | :error
  def to_sheets(data) do
    {:ok, shape_sheets(data)}
  rescue
    _ -> :error
  end

  defp shape_sheets([]), do: []

  defp shape_sheets([%{"name" => _, "rows" => _, "headers" => _} | _] = workbook), do: workbook

  defp shape_sheets(sheet_data) when is_list(sheet_data), do: shape_sheets(%{@unnamed => sheet_data})

  defp shape_sheets(workbook) when is_map(workbook) do
    Enum.map(workbook, fn {sheet_name, [first_row | _] = sheet_data} ->
      headers = Map.keys(first_row)
      rows = Enum.map(sheet_data, &get_headers(headers, &1))
      %{"name" => sheet_name, "headers" => headers, "rows" => rows}
    end)
  end

  defp build_workbook(sheets) do
    set_cell = fn {content, idx}, sheet, jdx ->
      Sheet.set_cell(sheet, "#{col(idx)}#{jdx}", to_cell(content))
    end

    Enum.reduce(sheets, %Workbook{}, fn %{"name" => name, "rows" => rows, "headers" => headers}, workbook ->
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
  end

  defp get_headers(headers, row) when is_struct(row), do: get_headers(headers, Map.from_struct(row))
  defp get_headers(headers, row), do: Enum.map(headers, &row[&1])

  defp to_cell(atom) when is_atom(atom), do: to_string(atom)
  defp to_cell(integer) when is_integer(integer), do: integer
  defp to_cell(float) when is_float(float), do: float
  defp to_cell(string) when is_binary(string), do: string
  defp to_cell(date) when is_struct(date, Date), do: to_string(date)
  defp to_cell(datetime) when is_struct(datetime, DateTime), do: to_string(datetime)
  defp to_cell(datetime) when is_struct(datetime, NaiveDateTime), do: to_string(datetime)
  defp to_cell(_otherwise), do: "(cannot convert)"

  defp to_list(struct) when is_struct(struct), do: to_list(Map.from_struct(struct))
  defp to_list(map) when is_map(map), do: Map.values(map)
  defp to_list(list) when is_list(list), do: list
end
