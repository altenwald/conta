defmodule Conta.Reconciliation.CsvImportTest do
  use ExUnit.Case

  alias Conta.Reconciliation.CsvImport

  test "parses a CSV binary into a list of maps keyed by header" do
    csv = "date,description,amount\n2026-07-01,NETFLIX,-13.99\n2026-07-02,SALARY,1500.00\n"

    assert {:ok, rows} = CsvImport.parse(csv)

    assert rows == [
             %{"date" => "2026-07-01", "description" => "NETFLIX", "amount" => "-13.99"},
             %{"date" => "2026-07-02", "description" => "SALARY", "amount" => "1500.00"}
           ]
  end

  test "returns an error for an empty file" do
    assert {:error, :empty_file} = CsvImport.parse("")
  end

  test "returns an error when a row has fewer columns than the header" do
    csv = "date,description,amount\n2026-07-01,NETFLIX\n"

    assert {:error, {:column_mismatch, 2}} = CsvImport.parse(csv)
  end

  test "returns an error when a row has more columns than the header" do
    csv = "date,description,amount\n2026-07-01,NETFLIX,-13.99,extra\n"

    assert {:error, {:column_mismatch, 2}} = CsvImport.parse(csv)
  end
end
