defmodule Conta.Reconciliation.CsvImport do
  @moduledoc """
  Parses a raw CSV binary (as uploaded for bank statement reconciliation)
  into a list of maps keyed by the CSV header row.
  """

  NimbleCSV.define(Parser, separator: ",", escape: "\"")

  @doc """
  Parses a CSV binary into `{:ok, rows}`, where `rows` is a list of maps
  keyed by the header row, or an error tuple when the input is malformed:

    * `{:error, :empty_file}` when the binary is empty.
    * `{:error, {:column_mismatch, line}}` when a data row doesn't have the
      same number of columns as the header. `line` is the 1-based line
      number within the CSV file (the header is line 1, so the first data
      row is line 2), matching what a user would see if they opened the
      file in a text editor or spreadsheet. Parsing stops at the first
      offending row.
  """
  def parse(""), do: {:error, :empty_file}

  def parse(binary) when is_binary(binary) do
    [header | rows] = Parser.parse_string(binary, skip_headers: false)
    header_size = length(header)

    rows
    |> Enum.with_index(2)
    |> Enum.reduce_while({:ok, []}, fn {row, line}, {:ok, acc} ->
      if length(row) == header_size do
        {:cont, {:ok, [Map.new(Enum.zip(header, row)) | acc]}}
      else
        {:halt, {:error, {:column_mismatch, line}}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end
end
