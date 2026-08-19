defmodule Conta.Reconciliation.ExcelImportTest do
  use ExUnit.Case, async: true

  alias Conta.Automator.Excel
  alias Conta.Reconciliation.ExcelImport

  describe "parse/1" do
    test "returns :empty_file when binary is empty" do
      assert ExcelImport.parse("") == {:error, :empty_file}
    end

    test "returns :invalid_excel when binary is not a valid zip archive" do
      assert ExcelImport.parse("not an excel file") == {:error, :invalid_excel}
    end

    test "parses a standard xlsx file into a list of maps keyed by headers" do
      data = %{
        "Sheet1" => [
          %{"Fecha" => "2026-07-01", "Concepto" => "Gasolina Repsol", "Importe" => "-50.00"},
          %{"Fecha" => "2026-07-02", "Concepto" => "Nómina", "Importe" => "2500.00"}
        ]
      }

      {:ok, {_filename, binary}} = Excel.export(data, "statement.xlsx")

      assert {:ok, rows} = ExcelImport.parse(binary)
      assert length(rows) == 2

      assert Enum.at(rows, 0) == %{
               "Fecha" => "2026-07-01",
               "Concepto" => "Gasolina Repsol",
               "Importe" => "-50.00"
             }

      assert Enum.at(rows, 1) == %{
               "Fecha" => "2026-07-02",
               "Concepto" => "Nómina",
               "Importe" => "2500.00"
             }
    end

    test "detects header row automatically when bank prepends metadata rows" do
      # Generates a workbook with metadata rows before headers:
      # Row 1: Titular: Mi Empresa SL
      # Row 2: IBAN: ES1234567890
      # Row 3: Fecha | Concepto | Importe
      # Row 4: 2026-07-10 | Factura 123 | -150.00
      sheet =
        Elixlsx.Sheet.with_name("Extracto")
        |> Elixlsx.Sheet.set_cell("A1", "Titular: Mi Empresa SL")
        |> Elixlsx.Sheet.set_cell("A2", "IBAN: ES1234567890")
        |> Elixlsx.Sheet.set_cell("A3", "Fecha")
        |> Elixlsx.Sheet.set_cell("B3", "Concepto")
        |> Elixlsx.Sheet.set_cell("C3", "Importe")
        |> Elixlsx.Sheet.set_cell("A4", "2026-07-10")
        |> Elixlsx.Sheet.set_cell("B4", "Factura 123")
        |> Elixlsx.Sheet.set_cell("C4", "-150.00")

      workbook = %Elixlsx.Workbook{sheets: [sheet]}
      {:ok, {_filename, binary}} = Elixlsx.write_to_memory(workbook, "bank.xlsx")

      assert {:ok, [row]} = ExcelImport.parse(binary)

      assert row == %{
               "Fecha" => "2026-07-10",
               "Concepto" => "Factura 123",
               "Importe" => "-150.00"
             }
    end

    test "parses an HTML table disguised as .xls (common banking format)" do
      html_xls = """
      <html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel">
      <head><meta charset="utf-8"/></head>
      <body>
        <table>
          <tr><td colspan="3"><b>Cuenta: ES1234567890</b></td></tr>
          <tr><td colspan="3">Saldo: 1.000,00 EUR</td></tr>
          <tr>
            <th>Fecha</th>
            <th>Concepto</th>
            <th>Importe</th>
          </tr>
          <tr>
            <td>2026-07-01</td>
            <td>Compra Supermercado</td>
            <td>-45.50</td>
          </tr>
          <tr>
            <td>2026-07-02</td>
            <td>Transferencia Recibida</td>
            <td>300.00</td>
          </tr>
        </table>
      </body>
      </html>
      """

      assert {:ok, rows} = ExcelImport.parse(html_xls)
      assert length(rows) == 2

      assert Enum.at(rows, 0) == %{
               "Fecha" => "2026-07-01",
               "Concepto" => "Compra Supermercado",
               "Importe" => "-45.50"
             }

      assert Enum.at(rows, 1) == %{
               "Fecha" => "2026-07-02",
               "Concepto" => "Transferencia Recibida",
               "Importe" => "300.00"
             }
    end

    test "parses a SpreadsheetML 2003 XML disguised as .xls" do
      xml_xls = """
      <?xml version="1.0"?>
      <?mso-application progid="Excel.Sheet"?>
      <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
       xmlns:o="urn:schemas-microsoft-com:office:office"
       xmlns:x="urn:schemas-microsoft-com:office:excel"
       xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet"
       xmlns:html="http://www.w3.org/TR/REC-html40">
       <Worksheet ss:Name="Movimientos">
        <Table>
         <Row>
          <Cell><Data ss:Type="String">Titular: Empresa SL</Data></Cell>
         </Row>
         <Row>
          <Cell><Data ss:Type="String">Fecha</Data></Cell>
          <Cell><Data ss:Type="String">Concepto</Data></Cell>
          <Cell><Data ss:Type="String">Importe</Data></Cell>
         </Row>
         <Row>
          <Cell><Data ss:Type="String">2026-07-05</Data></Cell>
          <Cell><Data ss:Type="String">Recibo Luz</Data></Cell>
          <Cell><Data ss:Type="String">-89.20</Data></Cell>
         </Row>
        </Table>
       </Worksheet>
      </Workbook>
      """

      assert {:ok, [row]} = ExcelImport.parse(xml_xls)

      assert row == %{
               "Fecha" => "2026-07-05",
               "Concepto" => "Recibo Luz",
               "Importe" => "-89.20"
             }
    end

    test "formats numeric values as exact fixed-point decimals with 2 decimal places" do
      sheet =
        Elixlsx.Sheet.with_name("Extracto")
        |> Elixlsx.Sheet.set_cell("A1", "Fecha")
        |> Elixlsx.Sheet.set_cell("B1", "Concepto")
        |> Elixlsx.Sheet.set_cell("C1", "Importe")
        |> Elixlsx.Sheet.set_cell("D1", "Saldo")
        |> Elixlsx.Sheet.set_cell("A2", "2026-08-01")
        |> Elixlsx.Sheet.set_cell("B2", "Comisión")
        |> Elixlsx.Sheet.set_cell("C2", -10)
        |> Elixlsx.Sheet.set_cell("D2", 1435)
        |> Elixlsx.Sheet.set_cell("A3", "2026-08-02")
        |> Elixlsx.Sheet.set_cell("B3", "Factura")
        |> Elixlsx.Sheet.set_cell("C3", 420.5)
        |> Elixlsx.Sheet.set_cell("D3", 1855.5)

      workbook = %Elixlsx.Workbook{sheets: [sheet]}
      {:ok, {_filename, binary}} = Elixlsx.write_to_memory(workbook, "decimals.xlsx")

      assert {:ok, rows} = ExcelImport.parse(binary)

      assert Enum.at(rows, 0) == %{
               "Fecha" => "2026-08-01",
               "Concepto" => "Comisión",
               "Importe" => "-10.00",
               "Saldo" => "1435.00"
             }

      assert Enum.at(rows, 1) == %{
               "Fecha" => "2026-08-02",
               "Concepto" => "Factura",
               "Importe" => "420.50",
               "Saldo" => "1855.50"
             }
    end

    test "parses BIFF8 OLE2 XLS stream with SST spanning multiple CONTINUE records" do
      # Construct an OLE2 binary containing an SST with CONTINUE records
      # SST with 3 strings where total data spans across SST (0x00FC) and CONTINUE (0x003C)
      str1 = "A" <> String.duplicate("x", 8219)
      str2 = "B" <> String.duplicate("y", 100)

      # Build SST record data
      sst_record = <<3::little-32, 3::little-32, 8220::little-16, 0::8, str1::binary>>
      # Split sst_record into max 8224-byte record + CONTINUE record
      <<sst_chunk1::binary-size(8224), sst_chunk2::binary>> = sst_record

      continue_chunk =
        <<0::8, sst_chunk2::binary, 101::little-16, 0::8, str2::binary, 6::little-16, 0::8, "Amount">>

      biff_stream =
        <<
          0x0809::little-16,
          8::little-16,
          0x0006::little-16,
          0x0010::little-16,
          0::little-32,
          0x00FC::little-16,
          8224::little-16,
          sst_chunk1::binary,
          0x003C::little-16,
          byte_size(continue_chunk)::little-16,
          continue_chunk::binary,
          # Headers: Row 0, Col 0 -> SST 2 ("Amount"), Col 1 -> SST 1 (str2)
          0x00FD::little-16,
          10::little-16,
          0::little-16,
          0::little-16,
          0::little-16,
          2::little-32,
          0x00FD::little-16,
          10::little-16,
          0::little-16,
          1::little-16,
          0::little-16,
          1::little-32,
          # Data: Row 1, Col 0 -> 100.0, Col 1 -> SST 0 (str1)
          0x0203::little-16,
          14::little-16,
          1::little-16,
          0::little-16,
          0::little-16,
          100.0::little-float-64,
          0x00FD::little-16,
          10::little-16,
          1::little-16,
          1::little-16,
          0::little-16,
          0::little-32,
          0x000A::little-16,
          0::little-16
        >>

      # Build minimal OLE2 structure around biff_stream
      # Sector size 512
      pad_size = 512 - rem(byte_size(biff_stream), 512)
      padded_stream = if pad_size == 512, do: biff_stream, else: biff_stream <> :binary.copy(<<0>>, pad_size)
      num_stream_sectors = div(byte_size(padded_stream), 512)

      # FAT: stream sectors 0..(num_stream_sectors-1), then directory sector at index num_stream_sectors
      dir_sec_idx = num_stream_sectors

      fat_entries =
        Enum.map(0..(num_stream_sectors - 2), fn i -> <<i + 1::little-32>> end) ++
          [<<0xFFFFFFFE::little-32>>, <<0xFFFFFFFE::little-32>>]

      fat_bytes = IO.iodata_to_binary(fat_entries)
      fat_pad = 512 - rem(byte_size(fat_bytes), 512)
      padded_fat = if fat_pad == 512, do: fat_bytes, else: fat_bytes <> :binary.copy(<<0xFF>>, fat_pad)
      fat_sec_idx = dir_sec_idx + 1

      # Directory entry for Workbook
      name_utf16 = :unicode.characters_to_binary("Workbook\0", :utf8, {:utf16, :little})
      name_pad = 64 - byte_size(name_utf16)
      padded_name = name_utf16 <> :binary.copy(<<0>>, name_pad)

      dir_entry_root = :binary.copy(<<0>>, 128)

      dir_entry_workbook =
        <<padded_name::binary-size(64), byte_size(name_utf16)::little-16, 2::8, 1::8, 0xFFFFFFFF::little-32,
          0xFFFFFFFF::little-32, 0xFFFFFFFF::little-32, 0::128, 0::little-32, 0::little-64, 0::little-64,
          0::little-32, byte_size(biff_stream)::little-64>>

      dir_sector = dir_entry_root <> dir_entry_workbook <> :binary.copy(<<0>>, 512 - 256)

      # DIFAT in header: points to fat_sec_idx
      difat = <<fat_sec_idx::little-32>> <> :binary.copy(<<0xFF>>, 432)

      ole2_header =
        <<0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0::128, 0x003E::little-16, 0x0003::little-16,
          0xFFFE::little-16, 9::little-16, 6::little-16, 0::48, 0::little-32, 1::little-32,
          dir_sec_idx::little-32, 0::little-32, 4096::little-32, 0xFFFFFFFE::little-32, 0::little-32,
          0xFFFFFFFE::little-32, 0::little-32, difat::binary-size(436)>>

      ole2_binary = ole2_header <> padded_stream <> dir_sector <> padded_fat

      assert {:ok, [row]} = ExcelImport.parse(ole2_binary)
      assert row["Amount"] == "100.00"
      assert row[str2] == str1
    end

    test "returns :no_headers_found when no row has multiple columns" do
      sheet =
        Elixlsx.Sheet.with_name("Extracto")
        |> Elixlsx.Sheet.set_cell("A1", "Solo una columna")
        |> Elixlsx.Sheet.set_cell("A2", "Otra fila con una columna")

      workbook = %Elixlsx.Workbook{sheets: [sheet]}
      {:ok, {_filename, binary}} = Elixlsx.write_to_memory(workbook, "empty_headers.xlsx")

      assert ExcelImport.parse(binary) == {:error, :no_headers_found}
    end
  end
end
