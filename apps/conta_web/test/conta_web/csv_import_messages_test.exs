defmodule ContaWeb.CsvImportMessagesTest do
  use ExUnit.Case, async: true

  alias ContaWeb.CsvImportMessages

  test "maps an empty upload entry list to a choose-a-file message" do
    assert CsvImportMessages.error_message([]) == "Please choose a file to upload"
  end

  test "maps the empty-file parse error to a message" do
    assert CsvImportMessages.error_message({:error, :empty_file}) == "The CSV data is empty"
  end

  test "maps a column-mismatch parse error to a message with the line number" do
    assert CsvImportMessages.error_message({:error, {:column_mismatch, 3}}) ==
             "Row 3 has a different number of columns than the header"
  end

  test "maps any other error reason to its inspected value" do
    assert CsvImportMessages.error_message({:error, :boom}) == inspect(:boom)
  end
end
