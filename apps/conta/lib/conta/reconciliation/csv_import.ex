defmodule Conta.Reconciliation.CsvImport do
  @moduledoc """
  Parses a raw CSV binary (as uploaded for bank statement reconciliation)
  into a list of maps keyed by the CSV header row.
  """

  NimbleCSV.define(Parser, separator: ",", escape: "\"")

  @doc """
  Parses a CSV binary into `{:ok, rows}`, where `rows` is a list of maps
  keyed by the header row, or `{:error, :empty_file}` when the binary is empty.
  """
  def parse(""), do: {:error, :empty_file}

  def parse(binary) when is_binary(binary) do
    [header | rows] = Parser.parse_string(binary, skip_headers: false)

    rows =
      Enum.map(rows, fn row ->
        header
        |> Enum.zip(row)
        |> Map.new()
      end)

    {:ok, rows}
  end
end
