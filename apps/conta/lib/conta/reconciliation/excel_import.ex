defmodule Conta.Reconciliation.ExcelImport do
  @moduledoc """
  Parses raw Excel (.xlsx and .xls) binaries into a list of maps keyed by the header row,
  automatically detecting the header row if the bank prepended metadata rows.

  Supports:
    * Standard .xlsx (OpenXML ZIP archives)
    * HTML tables exported with .xls extension (common in banking)
    * XML Spreadsheet 2003 exported with .xls extension
    * Binary BIFF8 / OLE2 (.xls)
  """

  import Bitwise

  @ole2_magic <<0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1>>
  @zip_magic <<0x50, 0x4B, 0x03, 0x04>>

  @doc """
  Parses an Excel binary into `{:ok, rows}` or `{:error, reason}`:
    * `{:error, :empty_file}` when binary is empty.
    * `{:error, :invalid_excel}` when binary is not a valid Excel format.
    * `{:error, :no_headers_found}` when no row contains valid table headers.
  """
  def parse(""), do: {:error, :empty_file}

  def parse(binary) when is_binary(binary) do
    cond do
      String.starts_with?(binary, @zip_magic) ->
        parse_xlsx(binary)

      String.starts_with?(binary, @ole2_magic) ->
        parse_biff8_ole2(binary)

      html_table?(binary) ->
        parse_html_table(binary)

      spreadsheet_xml?(binary) ->
        parse_spreadsheet_xml(binary)

      true ->
        {:error, :invalid_excel}
    end
  end

  def parse(_), do: {:error, :invalid_excel}

  # --- XLSX Parser ---

  defp parse_xlsx(binary) do
    case :zip.extract(binary, [:memory]) do
      {:ok, files} ->
        files_map = Map.new(files, fn {name, content} -> {to_string(name), content} end)
        shared_strings = parse_shared_strings(files_map["xl/sharedStrings.xml"])
        sheet_xml = find_sheet_xml(files_map)

        if sheet_xml do
          parse_sheet(sheet_xml, shared_strings)
        else
          {:error, :invalid_excel}
        end

      {:error, _} ->
        {:error, :invalid_excel}
    end
  end

  defp find_sheet_xml(files_map) do
    files_map["xl/worksheets/sheet1.xml"] ||
      Enum.find_value(files_map, fn {name, content} ->
        if String.starts_with?(name, "xl/worksheets/sheet") and String.ends_with?(name, ".xml"),
          do: content
      end)
  end

  defp parse_shared_strings(nil), do: %{}

  defp parse_shared_strings(xml) do
    Regex.scan(~r/<si\b[^>]*>(.*?)<\/si>/s, xml)
    |> Enum.with_index()
    |> Map.new(fn {[_, si_content], index} ->
      text =
        Regex.scan(~r/<t\b[^>]*>(.*?)<\/t>/s, si_content)
        |> Enum.map_join("", fn [_, t] -> unescape_xml(t) end)

      {index, text}
    end)
  rescue
    _ -> %{}
  end

  defp parse_sheet(sheet_xml, shared_strings) do
    rows =
      Regex.scan(~r/<row\b[^>]*>(.*?)<\/row>/s, sheet_xml)
      |> Enum.map(fn [_, row_content] -> parse_row_cells(row_content, shared_strings) end)

    detect_headers_and_build_rows(rows)
  end

  defp parse_row_cells(row_content, shared_strings) do
    Regex.scan(~r/<c\b([^>]*)>(.*?)<\/c>/s, row_content)
    |> Enum.reduce(%{}, fn match, acc -> parse_cell_match(match, shared_strings, acc) end)
    |> build_row_from_cells_map()
  end

  defp parse_cell_match([_, attrs, body], shared_strings, acc) do
    case extract_cell_ref(attrs) do
      nil ->
        acc

      ref ->
        col_idx = col_to_index(Regex.replace(~r/[0-9]/, ref, ""))
        type = extract_cell_type(attrs)
        v_val = extract_tag_value(body, ~r/<v\b[^>]*>(.*?)<\/v>/s)
        t_val = extract_tag_value(body, ~r/<t\b[^>]*>(.*?)<\/t>/s)
        value = extract_cell_value(type, v_val, t_val, shared_strings)
        Map.put(acc, col_idx, value)
    end
  end

  defp extract_cell_ref(attrs) do
    case Regex.run(~r/r="([A-Z]+[0-9]+)"/, attrs) do
      [_, r] -> r
      _ -> nil
    end
  end

  defp extract_cell_type(attrs) do
    case Regex.run(~r/t="([a-z]+)"/, attrs) do
      [_, t] -> t
      _ -> "n"
    end
  end

  defp extract_tag_value(body, regex) do
    case Regex.run(regex, body) do
      [_, val] -> val
      _ -> nil
    end
  end

  defp extract_cell_value("s", v_val, _t_val, shared_strings) when is_binary(v_val) do
    idx = String.to_integer(String.trim(v_val))
    Map.get(shared_strings, idx, "")
  end

  defp extract_cell_value("inlineStr", _v_val, t_val, _shared_strings) when is_binary(t_val) do
    unescape_xml(t_val)
  end

  defp extract_cell_value("b", v_val, _t_val, _shared_strings) when is_binary(v_val) do
    if String.trim(v_val) == "1", do: "true", else: "false"
  end

  defp extract_cell_value(_type, v_val, _t_val, _shared_strings) when is_binary(v_val) do
    format_num(unescape_xml(String.trim(v_val)))
  end

  defp extract_cell_value(_type, _v_val, t_val, _shared_strings) when is_binary(t_val) do
    unescape_xml(String.trim(t_val))
  end

  defp extract_cell_value(_type, _v_val, _t_val, _shared_strings), do: ""

  defp build_row_from_cells_map(cells_map) when map_size(cells_map) == 0, do: []

  defp build_row_from_cells_map(cells_map) do
    max_col = Enum.max(Map.keys(cells_map))
    Enum.map(1..max_col, fn idx -> Map.get(cells_map, idx, "") end)
  end

  defp col_to_index(col_str) do
    col_str
    |> String.upcase()
    |> String.to_charlist()
    |> Enum.reduce(0, fn char, acc -> acc * 26 + (char - ?A + 1) end)
  end

  # --- HTML Table Parser (Common Bank .xls format) ---

  defp html_table?(binary) do
    String.contains?(binary, "<table") or
      String.contains?(binary, "<TABLE") or
      (String.contains?(binary, "<html") and String.contains?(binary, "<tr"))
  end

  defp parse_html_table(html) do
    rows =
      Regex.scan(~r/<tr\b[^>]*>(.*?)<\/tr>/si, html)
      |> Enum.map(fn [_, tr_content] ->
        Regex.scan(~r/<t[hd]\b[^>]*>(.*?)<\/t[hd]>/si, tr_content)
        |> Enum.map(fn [_, td_content] ->
          td_content
          |> String.replace(~r/<[^>]+>/, "")
          |> unescape_html()
          |> String.trim()
        end)
      end)

    detect_headers_and_build_rows(rows)
  end

  # --- SpreadsheetML 2003 XML Parser ---

  defp spreadsheet_xml?(binary) do
    (String.contains?(binary, "<?xml") or String.contains?(binary, "<Workbook")) and
      (String.contains?(binary, "urn:schemas-microsoft-com:office:spreadsheet") or
         String.contains?(binary, "<Table"))
  end

  defp parse_spreadsheet_xml(xml) do
    rows =
      Regex.scan(~r/<Row\b[^>]*>(.*?)<\/Row>/si, xml)
      |> Enum.map(fn [_, row_content] ->
        Regex.scan(~r/<Cell\b[^>]*>(?:.*?<Data\b[^>]*>(.*?)<\/Data>)?.*?<\/Cell>/si, row_content)
        |> Enum.map(fn match ->
          data_val = Enum.at(match, 1) || ""
          data_val |> String.replace(~r/<[^>]+>/, "") |> unescape_xml() |> String.trim()
        end)
      end)

    detect_headers_and_build_rows(rows)
  end

  # --- BIFF8 / OLE2 Binary Parser ---

  defp parse_biff8_ole2(binary) do
    case extract_ole2_stream(binary, ["Workbook", "Book", "WORKBOOK", "BOOK"]) do
      {:ok, workbook_stream} ->
        parse_biff8_stream(workbook_stream)

      {:error, _} ->
        {:error, :invalid_excel}
    end
  end

  defp extract_ole2_stream(binary, target_names) do
    case binary do
      <<@ole2_magic, _clsid::binary-size(16), _minor_ver::little-16, _major_ver::little-16,
        _byte_order::little-16, sector_shift::little-16, _mini_sector_shift::little-16,
        _reserved::binary-size(6), _num_dir_sectors::little-32, _num_fat_sectors::little-32,
        first_dir_sector::little-32, _txn_sig::little-32, _mini_stream_cutoff::little-32,
        _first_mini_fat_sector::little-32, _num_mini_fat_sectors::little-32, _first_difat_sector::little-32,
        _num_difat_sectors::little-32, difat_initial::binary-size(436), rest_of_file::binary>> ->
        sector_size = 1 <<< sector_shift

        # Read FAT sector IDs from initial DIFAT array
        fat_sector_ids =
          for <<sec_id::little-32 <- difat_initial>>, sec_id != 0xFFFFFFFE and sec_id != 0xFFFFFFFF,
            do: sec_id

        # Extract all sectors
        sectors =
          rest_of_file
          |> chunk_binary(sector_size)

        # Build FAT table
        fat_table =
          fat_sector_ids
          |> collect_sectors(sectors)
          |> for_fat_entries()

        # Traverse Directory chain
        dir_chain = get_sector_chain(first_dir_sector, fat_table)
        dir_binary = collect_sectors(dir_chain, sectors)

        # Parse 128-byte directory entries
        dir_entries =
          for <<entry::binary-size(128) <- dir_binary>> do
            parse_dir_entry(entry)
          end

        find_target_stream(dir_entries, target_names, fat_table, sectors, sector_size)

      _ ->
        {:error, :invalid_ole2}
    end
  end

  defp find_target_stream(dir_entries, target_names, fat_table, sectors, sector_size) do
    case Enum.find(dir_entries, fn e -> e.name in target_names end) do
      nil ->
        {:error, :stream_not_found}

      target_entry ->
        stream_chain = get_sector_chain(target_entry.start_sector, fat_table)

        stream_binary =
          stream_chain
          |> collect_sectors(sectors)
          |> binary_part(0, min(target_entry.size, length(stream_chain) * sector_size))

        {:ok, stream_binary}
    end
  end

  defp collect_sectors(chain, sectors) do
    Enum.map_join(chain, "", fn id -> Enum.at(sectors, id, "") end)
  end

  defp parse_dir_entry(
         <<name_utf16::binary-size(64), name_len::little-16, type::8, _color::8, _left::little-32,
           _right::little-32, _child::little-32, _clsid::binary-size(16), _flags::little-32,
           _created::binary-size(8), _modified::binary-size(8), start_sector::little-32, size::little-64>>
       ) do
    # name_len includes null terminator in bytes
    real_len = max(0, name_len - 2)
    name_bytes = binary_part(name_utf16, 0, min(real_len, 64))

    name =
      case :unicode.characters_to_binary(name_bytes, {:utf16, :little}, :utf8) do
        s when is_binary(s) -> s
        _ -> ""
      end

    %{name: name, type: type, start_sector: start_sector, size: size}
  end

  defp parse_dir_entry(_), do: %{name: "", type: 0, start_sector: 0, size: 0}

  defp chunk_binary(binary, chunk_size) do
    chunk_binary(binary, chunk_size, [])
  end

  defp chunk_binary(<<>>, _chunk_size, acc), do: Enum.reverse(acc)

  defp chunk_binary(binary, chunk_size, acc) do
    if byte_size(binary) >= chunk_size do
      <<chunk::binary-size(chunk_size), rest::binary>> = binary
      chunk_binary(rest, chunk_size, [chunk | acc])
    else
      Enum.reverse([binary | acc])
    end
  end

  defp for_fat_entries(fat_bytes) do
    for <<next_sec::little-32 <- fat_bytes>>, do: next_sec
  end

  defp get_sector_chain(start_sec, fat_table) do
    get_sector_chain(start_sec, fat_table, [])
  end

  defp get_sector_chain(sec, _fat_table, acc) when sec >= 0xFFFFFFFC or sec < 0 do
    Enum.reverse(acc)
  end

  defp get_sector_chain(sec, fat_table, acc) do
    if sec in acc or sec >= length(fat_table) do
      Enum.reverse(acc)
    else
      next_sec = Enum.at(fat_table, sec, 0xFFFFFFFE)
      get_sector_chain(next_sec, fat_table, [sec | acc])
    end
  end

  defp parse_biff8_stream(stream) do
    {_sst, cell_values} = read_biff8_records(stream, %{}, %{})

    if map_size(cell_values) == 0 do
      {:error, :no_headers_found}
    else
      rows_map =
        Enum.group_by(
          Map.to_list(cell_values),
          fn {{row, _col}, _val} -> row end,
          fn {{_row, col}, val} -> {col, val} end
        )

      rows =
        rows_map
        |> Map.keys()
        |> Enum.sort()
        |> Enum.map(&build_biff8_row(rows_map, &1))

      detect_headers_and_build_rows(rows)
    end
  rescue
    _ -> {:error, :invalid_excel}
  end

  defp build_biff8_row(rows_map, row_idx) do
    cols = Map.new(Map.get(rows_map, row_idx, []))
    max_col = if map_size(cols) == 0, do: 0, else: Enum.max(Map.keys(cols))
    Enum.map(0..max_col, fn c -> Map.get(cols, c, "") end)
  end

  defp read_biff8_records(<<>>, _sst, cells), do: {%{}, cells}

  defp read_biff8_records(
         <<type::little-16, len::little-16, data::binary-size(len), rest::binary>>,
         sst,
         cells
       ) do
    case type do
      # SST (Shared String Table)
      0x00FC ->
        {continue_chunks, rest_stream} = collect_biff_continues(rest, [])
        new_sst = parse_biff_sst([data | continue_chunks])
        read_biff8_records(rest_stream, new_sst, cells)

      # LABELSST
      0x00FD ->
        <<row::little-16, col::little-16, _xf::little-16, sst_idx::little-32>> = data
        val = Map.get(sst, sst_idx, "")
        read_biff8_records(rest, sst, Map.put(cells, {row, col}, val))

      # LABEL
      0x0204 ->
        <<row::little-16, col::little-16, _xf::little-16, str_len::little-16, flags::8, str_bytes::binary>> =
          data

        val = decode_biff_string(str_bytes, str_len, flags)
        read_biff8_records(rest, sst, Map.put(cells, {row, col}, val))

      # NUMBER
      0x0203 ->
        <<row::little-16, col::little-16, _xf::little-16, num::little-float-64>> = data
        val = format_num(num)
        read_biff8_records(rest, sst, Map.put(cells, {row, col}, val))

      # RK
      0x027E ->
        <<row::little-16, col::little-16, _xf::little-16, rk::little-32>> = data
        val = decode_rk(rk)
        read_biff8_records(rest, sst, Map.put(cells, {row, col}, val))

      # MULRK
      0x00BD ->
        <<row::little-16, first_col::little-16, mul_data::binary>> = data
        rk_cells = parse_mulrk(row, first_col, mul_data)
        read_biff8_records(rest, sst, Map.merge(cells, rk_cells))

      _other ->
        read_biff8_records(rest, sst, cells)
    end
  rescue
    _ -> {%{}, cells}
  end

  defp read_biff8_records(_incomplete, _sst, cells), do: {%{}, cells}

  defp collect_biff_continues(
         <<0x003C::little-16, len::little-16, data::binary-size(len), rest::binary>>,
         acc
       ) do
    collect_biff_continues(rest, [data | acc])
  end

  defp collect_biff_continues(rest, acc) do
    {Enum.reverse(acc), rest}
  end

  defp parse_biff_sst([<<_total::little-32, unique::little-32, first_data::binary>> | continue_chunks]) do
    chunks = [first_data | continue_chunks]
    parse_biff_sst_strings(chunks, unique, 0, %{})
  end

  defp parse_biff_sst(_), do: %{}

  defp parse_biff_sst_strings(_chunks, count, idx, acc) when idx >= count, do: acc
  defp parse_biff_sst_strings([], _count, _idx, acc), do: acc

  defp parse_biff_sst_strings(chunks, count, idx, acc) do
    case read_sst_bytes(3, chunks) do
      {:ok, <<char_len::little-16, flags::8>>, chunks1} ->
        is_unicode? = (flags &&& 0x01) != 0
        has_rich_text? = (flags &&& 0x08) != 0
        has_phonetic? = (flags &&& 0x04) != 0

        {rich_runs, phonetic_size, chunks2} =
          parse_sst_rich_and_phonetic(has_rich_text?, has_phonetic?, chunks1)

        {:ok, str, chunks3} = read_sst_string_chars(char_len, is_unicode?, chunks2)
        skip_bytes = rich_runs * 4 + phonetic_size
        chunks4 = skip_sst_bytes(skip_bytes, chunks3)

        parse_biff_sst_strings(chunks4, count, idx + 1, Map.put(acc, idx, str))

      _ ->
        acc
    end
  rescue
    _ -> acc
  end

  defp parse_sst_rich_and_phonetic(true, true, chunks1) do
    case read_sst_bytes(6, chunks1) do
      {:ok, <<r_runs::little-16, p_size::little-32>>, c} -> {r_runs, p_size, c}
      _ -> {0, 0, chunks1}
    end
  end

  defp parse_sst_rich_and_phonetic(true, false, chunks1) do
    case read_sst_bytes(2, chunks1) do
      {:ok, <<r_runs::little-16>>, c} -> {r_runs, 0, c}
      _ -> {0, 0, chunks1}
    end
  end

  defp parse_sst_rich_and_phonetic(false, true, chunks1) do
    case read_sst_bytes(4, chunks1) do
      {:ok, <<p_size::little-32>>, c} -> {0, p_size, c}
      _ -> {0, 0, chunks1}
    end
  end

  defp parse_sst_rich_and_phonetic(false, false, chunks1), do: {0, 0, chunks1}

  defp skip_sst_bytes(skip_bytes, chunks) do
    case read_sst_bytes(skip_bytes, chunks) do
      {:ok, _skipped, c} -> c
      _ -> chunks
    end
  end

  defp read_sst_bytes(0, chunks), do: {:ok, <<>>, chunks}
  defp read_sst_bytes(_count, []), do: {:error, :eof}
  defp read_sst_bytes(count, [<<>> | rest_chunks]), do: read_sst_bytes(count, rest_chunks)

  defp read_sst_bytes(count, [chunk | rest_chunks]) do
    chunk_size = byte_size(chunk)

    if chunk_size >= count do
      <<bytes::binary-size(count), rest_chunk::binary>> = chunk
      {:ok, bytes, [rest_chunk | rest_chunks]}
    else
      needed = count - chunk_size

      case read_sst_bytes(needed, rest_chunks) do
        {:ok, more_bytes, final_chunks} ->
          {:ok, chunk <> more_bytes, final_chunks}

        error ->
          error
      end
    end
  end

  defp read_sst_string_chars(0, _is_unicode?, chunks), do: {:ok, "", chunks}
  defp read_sst_string_chars(_char_len, _is_unicode?, []), do: {:ok, "", []}

  defp read_sst_string_chars(char_len, is_unicode?, [<<>> | rest]),
    do: read_sst_string_chars(char_len, is_unicode?, rest)

  defp read_sst_string_chars(char_len, is_unicode?, [chunk | rest_chunks]) do
    bytes_per_char = if is_unicode?, do: 2, else: 1
    avail_chars = div(byte_size(chunk), bytes_per_char)

    if avail_chars >= char_len do
      needed_bytes = char_len * bytes_per_char
      <<str_bytes::binary-size(needed_bytes), rest_chunk::binary>> = chunk
      str = decode_biff_raw_bytes(str_bytes, is_unicode?)
      {:ok, str, [rest_chunk | rest_chunks]}
    else
      take_bytes = avail_chars * bytes_per_char
      <<str_bytes::binary-size(take_bytes), _unused::binary>> = chunk
      str1 = decode_biff_raw_bytes(str_bytes, is_unicode?)
      remaining_chars = char_len - avail_chars

      case skip_empty_sst_chunks(rest_chunks) do
        [<<continue_flag::8, next_data::binary>> | more_chunks] ->
          new_unicode? = (continue_flag &&& 0x01) != 0

          {:ok, str2, final_chunks} =
            read_sst_string_chars(remaining_chars, new_unicode?, [next_data | more_chunks])

          {:ok, str1 <> str2, final_chunks}

        _ ->
          {:ok, str1, []}
      end
    end
  end

  defp skip_empty_sst_chunks([<<>> | rest]), do: skip_empty_sst_chunks(rest)
  defp skip_empty_sst_chunks(other), do: other

  defp decode_biff_raw_bytes(bytes, true) do
    case :unicode.characters_to_binary(bytes, {:utf16, :little}, :utf8) do
      s when is_binary(s) -> s
      _ -> ""
    end
  end

  defp decode_biff_raw_bytes(bytes, false) do
    case :unicode.characters_to_binary(bytes, :latin1, :utf8) do
      s when is_binary(s) -> s
      _ -> ""
    end
  end

  defp decode_biff_string(bytes, _len, flags) do
    if (flags &&& 0x01) != 0 do
      case :unicode.characters_to_binary(bytes, {:utf16, :little}, :utf8) do
        s when is_binary(s) -> s
        _ -> ""
      end
    else
      case :unicode.characters_to_binary(bytes, :latin1, :utf8) do
        s when is_binary(s) -> s
        _ -> ""
      end
    end
  end

  defp decode_rk(rk) do
    is_100x = (rk &&& 0x01) != 0
    is_int = (rk &&& 0x02) != 0
    <<signed_val::signed-30, _::2>> = <<rk::32>>

    cond do
      is_int and is_100x ->
        format_num(signed_val / 100.0)

      is_int ->
        format_num(signed_val)

      is_100x ->
        <<f::float-64>> = <<rk &&& 0xFFFFFFFC::32, 0::32>>
        format_num(f / 100.0)

      true ->
        <<f::float-64>> = <<rk &&& 0xFFFFFFFC::32, 0::32>>
        format_num(f)
    end
  end

  defp parse_mulrk(row, first_col, data) do
    parse_mulrk_entries(row, first_col, data, %{})
  end

  defp parse_mulrk_entries(_row, _col, <<_last_col::little-16>>, acc), do: acc

  defp parse_mulrk_entries(row, col, <<_xf::little-16, rk::little-32, rest::binary>>, acc) do
    val = decode_rk(rk)
    parse_mulrk_entries(row, col + 1, rest, Map.put(acc, {row, col}, val))
  end

  defp parse_mulrk_entries(_row, _col, _other, acc), do: acc

  defp format_num(num) when is_float(num) do
    :erlang.float_to_binary(num, decimals: 2)
  end

  defp format_num(num) when is_integer(num) do
    "#{num}.00"
  end

  defp format_num(num) when is_binary(num) do
    trimmed = String.trim(num)

    case Float.parse(trimmed) do
      {float_val, ""} ->
        :erlang.float_to_binary(float_val, decimals: 2)

      _ ->
        trimmed
    end
  end

  # --- Helpers ---

  defp detect_headers_and_build_rows(rows) do
    max_non_empty =
      rows
      |> Enum.map(fn row -> Enum.count(row, fn v -> is_binary(v) and String.trim(v) != "" end) end)
      |> Enum.max(fn -> 0 end)

    min_cols = if max_non_empty >= 3, do: min(3, max_non_empty), else: 2

    header_index =
      Enum.find_index(rows, fn row ->
        non_empty = Enum.filter(row, fn v -> is_binary(v) and String.trim(v) != "" end)
        length(non_empty) >= min_cols
      end)

    case header_index do
      nil ->
        {:error, :no_headers_found}

      idx ->
        header_row = Enum.at(rows, idx)
        headers = Enum.map(header_row, &String.trim/1)
        data_rows = Enum.drop(rows, idx + 1)

        parsed_rows =
          data_rows
          |> Enum.reject(&empty_row?/1)
          |> Enum.map(&build_row_map(headers, &1))

        {:ok, parsed_rows}
    end
  end

  defp empty_row?(row) do
    Enum.all?(row, fn v -> is_nil(v) or String.trim(to_string(v)) == "" end)
  end

  defp build_row_map(headers, row) do
    padding = List.duplicate("", max(0, length(headers) - length(row)))

    headers
    |> Enum.zip(row ++ padding)
    |> Enum.reject(fn {k, _v} -> k == "" end)
    |> Map.new(fn {k, v} -> {k, trim_or_to_string(v)} end)
  end

  defp trim_or_to_string(v) when is_binary(v), do: String.trim(v)
  defp trim_or_to_string(v), do: to_string(v)

  defp unescape_xml(string) do
    string
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
  end

  defp unescape_html(string) do
    string
    |> unescape_xml()
    |> String.replace("&nbsp;", " ")
    |> String.replace("&euro;", "EUR")
    |> String.replace("&#128;", "EUR")
    |> String.replace("&#x20AC;", "EUR")
  end
end
