# Especificación de Diseño: Soporte para Ficheros Excel .xls en Conciliación

**Fecha:** 2026-08-19  
**Autor:** Antigravity  
**Estado:** Borrador de Diseño

---

## 1. Contexto y Motivación

Muchos bancos (especialmente banca corporativa y plataformas bancarias tradicionales en España e internacionalmente) ofrecen exportaciones con extensión `.xls`. En la práctica, los archivos con extensión `.xls` emitidos por entidades financieras pueden pertenecer a tres categorías:

1. **HTML disfrazado de .xls**: Un documento HTML (`<table><tr><td>...</td></tr></table>`) guardado con extensión `.xls`.
2. **SpreadsheetML 2003 XML**: Formato XML de Excel 2003 (`<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet">`).
3. **Binario BIFF8 / OLE2**: Formato binario nativo de Excel 97-2004 (`Compound Document Format`).

Para garantizar compatibilidad total con cualquier banco, el importador de conciliación debe detectar automáticamente el formato del contenido y extraer las filas en una estructura uniforme de mapas `[%{"Cabecera" => "Valor"}]`.

---

## 2. Alcance

1. **Ampliación de `Conta.Reconciliation.ExcelImport` (o módulo de soporte)**:
   - Detección de tipo de archivo mediante magic bytes / prefijo de contenido:
     - Zip / OPC (`PK..`) -> Flujo existente `.xlsx`.
     - OLE2 Compound Document (`<<0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1>>`) -> Parser BIFF8.
     - HTML (`<html`, `<!DOCTYPE`, `<table`) -> Parser HTML de tablas bancarias.
     - XML SpreadsheetML 2003 (`<?xml` con namespace `office:spreadsheet`) -> Parser SpreadsheetML.
   - En todos los casos, aplicar la detección inteligente de cabecera y extracción de mapas.

2. **Ampliación de `ContaWeb.ReconciliationLive.Upload`**:
   - `allow_upload(:statement, accept: ~w(.csv .xlsx .xls), max_entries: 1)`.
   - Si la extensión es `.xls` o `.xlsx`, usar `ExcelImport.parse/1`.
   - Si la extensión es `.csv`, usar `CsvImport.parse/1`.

---

## 3. Arquitectura del Parser .xls

### 3.1. Detección de Formato
```elixir
def parse(binary) when is_binary(binary) do
  cond do
    byte_size(binary) == 0 ->
      {:error, :empty_file}

    String.starts_with?(binary, "PK\x03\x04") ->
      parse_xlsx(binary)

    String.starts_with?(binary, <<0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1>>) ->
      parse_biff8_ole2(binary)

    html_table?(binary) ->
      parse_html_table(binary)

    spreadsheet_xml?(binary) ->
      parse_spreadsheet_xml(binary)

    true ->
      {:error, :invalid_excel}
  end
end
```

### 3.2. Parser de Tablas HTML (Disguised .xls)
- Escanea etiquetas `<tr[^>]*>(.*?)<\/tr>`.
- Dentro de cada `<tr>`, escanea `<t[hd][^>]*>(.*?)<\/t[hd]>`.
- Limpia etiquetas HTML internas (ej. `<span>`, `<font>`, `<b>`) y entidades (`&nbsp;`, `&euro;`, `&amp;`).
- Convierte en matriz de filas `[[celda1, celda2, ...]]`.
- Pasa la matriz a `detect_headers_and_build_rows/1`.

### 3.3. Parser de SpreadsheetML 2003
- Escanea `<Row[^>]*>(.*?)<\/Row>`.
- Dentro de cada fila, escanea `<Cell[^>]*>(?:.*?<Data[^>]*>(.*?)<\/Data>)?.*?<\/Cell>`.
- Pasa la matriz a `detect_headers_and_build_rows/1`.

### 3.4. Parser BIFF8 / OLE2
- Extrae el stream `Workbook` del contenedor OLE2.
- Lee los registros BIFF8:
  - `SST` (0x00FC): decodifica strings compartidas.
  - `LABELSST` (0x00FD): mapea celda a string en SST.
  - `LABEL` (0x0204): string directa en celda.
  - `NUMBER` (0x0203): número flotante (IEEE 754).
  - `RK` (0x027E) / `MULRK` (0x00BD): números enteros / RK decodificados.
- Genera la matriz de filas y pasa a `detect_headers_and_build_rows/1`.

---

## 4. Pruebas y Validación (TDD)

- Pruebas unitarias en `excel_import_test.exs`:
  - Fichero `.xls` con formato HTML table bancario (Santander/BBVA).
  - Fichero `.xls` con formato XML SpreadsheetML 2003.
  - Fichero `.xls` con formato binario BIFF8 / OLE2.
  - Fichero `.xlsx` OpenXML (regresión).
- Pruebas de integración LiveView en `upload_test.exs`:
  - Subida de fichero `.xls` y verificación de movimientos generados.
