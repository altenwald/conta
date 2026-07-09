defmodule Conta.Automator.ExcelTest do
  use ExUnit.Case, async: true

  alias Conta.Automator.Excel

  describe "to_sheets/1" do
    test "returns {:ok, []} for an empty list" do
      assert {:ok, []} = Excel.to_sheets([])
    end

    test "returns {:ok, []} for an empty map" do
      assert {:ok, []} = Excel.to_sheets(%{})
    end

    test "passes through an explicit name/headers/rows shape untouched" do
      workbook = [%{"name" => "Sheet1", "headers" => ["a", "b"], "rows" => [[1, 2]]}]
      assert {:ok, ^workbook} = Excel.to_sheets(workbook)
    end

    test "derives headers and rows from a plain list of maps" do
      data = [%{"a" => 1, "b" => 2}, %{"a" => 3, "b" => 4}]

      assert {:ok, [%{"name" => "No name", "headers" => headers, "rows" => rows}]} =
               Excel.to_sheets(data)

      assert Enum.sort(headers) == ["a", "b"]
      assert length(rows) == 2
    end

    test "derives one sheet per key for a map of sheet_name => rows" do
      data = %{"expenses" => [%{"amount" => 100}], "invoices" => [%{"amount" => 200}]}

      assert {:ok, sheets} = Excel.to_sheets(data)
      assert length(sheets) == 2
      assert Enum.all?(sheets, &(&1["headers"] == ["amount"]))
    end

    test "returns :error for a scalar result" do
      assert :error = Excel.to_sheets(42)
      assert :error = Excel.to_sheets("just a string")
    end

    test "returns :error for a list that isn't map-shaped" do
      assert :error = Excel.to_sheets([1, 2, 3])
    end
  end

  describe "export/2 regression" do
    test "completes for an empty list instead of recursing forever" do
      task = Task.async(fn -> Excel.export([], "empty.xlsx") end)
      assert {:ok, {_filename, _content}} = Task.await(task, 10_000)
    end
  end

  describe "to_cell/1" do
    test "passes scalar values through and falls back for anything else" do
      assert Excel.to_cell("plain string") == "plain string"
      assert Excel.to_cell(%{"a" => 1}) == "(cannot convert)"
    end
  end
end
