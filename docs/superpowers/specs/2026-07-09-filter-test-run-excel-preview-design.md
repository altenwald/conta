# Vista previa en tabla para el test-run de filtros con salida Excel

## Contexto

En `/automation/filters/:id/edit` (y `/new`), el panel "Test data" de `ContaWeb.FilterLive.Form` permite ejecutar el código Lua de un filtro contra parámetros de prueba (`handle_event("test_run", ...)`, `apps/conta_web/lib/conta_web/live/filter_live/form.ex:96-106`). El resultado se formatea siempre igual, sin mirar el campo `output` del filtro (`:json` o `:xlsx`):

```elixir
defp format_test_result({:ok, result}), do: {:ok, Jason.encode!(result, pretty: true)}
defp format_test_result({:error, reason}), do: {:error, inspect(reason)}
```

y se renderiza siempre como texto crudo en un `<pre>` (`apps/conta_web/lib/conta_web/live/filter_live/form.html.heex:71-74`).

Cuando el usuario elige "Excel" como formato de salida del filtro, el endpoint de descarga real (`ContaWeb.Api.Automator.Filter.run/2` → `Conta.Automator.run_filter/3`, `apps/conta/lib/conta/automator.ex:209-224`) ya construye correctamente un `.xlsx` con `Conta.Automator.Excel.export/2`, que acepta tres formas de datos:

- lista de mapas ya con `"name"`, `"headers"`, `"rows"` (multi-hoja explícita) — `apps/conta/lib/conta/automator/excel.ex:17`
- lista simple de mapas (registros) — deriva `headers` de `Map.keys/1` del primer mapa — `excel.ex:44`
- mapa `nombre_hoja => lista_de_mapas` — mismo derive, una hoja por clave — `excel.ex:46-54`

Pero el panel de pruebas del editor nunca usa esta lógica: siempre muestra el JSON crudo, incluso con `output: :xlsx`. Este documento cubre **solo** ese panel de pruebas; el endpoint de descarga real no cambia.

## Alcance

1. `Conta.Automator.Excel` expone una función pública `to_sheets/1` que normaliza cualquiera de las tres formas de arriba a `{:ok, sheets}` (lista de `%{"name"=>, "headers"=>, "rows"=>}`), o `:error` si el dato no tiene ninguna de esas formas.
2. `FilterLive.Form.handle_event("test_run", ...)` lee el `output` actual del formulario y construye un resultado etiquetado según ese output y la forma del dato devuelto por el script.
3. `form.html.heex` renderiza tabla(s) HTML cuando corresponde, en vez de JSON.
4. No se toca `ShortcutLive.Form` (los shortcuts no tienen campo `output`), ni el endpoint de descarga real, ni el formato del `.xlsx` generado.

## 1. `Conta.Automator.Excel` — extraer y exponer la normalización

Hoy la lógica de dar forma a las hojas está repartida entre las cláusulas de `export/2` (`apps/conta/lib/conta/automator/excel.ex:15-54`). Se extrae a una función privada `shape_sheets/1` con las mismas cuatro cláusulas (vacío, lista con headers/rows explícitos, lista simple, mapa de hojas), y `export/2` pasa a apoyarse en ella:

```elixir
def export(data, filename) do
  data
  |> shape_sheets()
  |> build_workbook()
  |> Elixlsx.write_to_memory(filename)
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
        row |> to_list() |> Enum.with_index(1) |> Enum.reduce(sheet, &set_cell.(&1, &2, i))
      end)

    Workbook.append_sheet(workbook, sheet)
  end)
end
```

El comportamiento observable de `export/2` no cambia para las entradas con datos, pero **sí corrige un bug preexistente en `export([], filename)`**: hoy esa cláusula delega a `export(%{}, filename)`, que entra en la rama `is_map`, hace `Enum.map(%{}, fn ...) end)` (que da `[]` sin invocar la función), y vuelve a llamar `export([], filename)` — recursión infinita real (verificado trazando el código; `export([], "x.xlsx")` con el código actual nunca retorna). Las nuevas cláusulas de `shape_sheets/1` no reproducen esa recursión (`shape_sheets([])` retorna `[]` directamente, sin volver a pasar por la rama de mapa), así que `export([], filename)` pasa de colgarse indefinidamente a completarse con un workbook vacío. Se documenta aquí como una corrección deliberada y bienvenida, no como scope creep: no estaba pedida, pero es consecuencia directa e inevitable de unificar la normalización en una sola función, y deja de bloquear cualquier caso (incluida la vista previa de este documento) donde el resultado del script sea `[]`.

Función pública nueva, único punto de entrada usado por la vista previa:

```elixir
@spec to_sheets(term()) :: {:ok, [map()]} | :error
def to_sheets(data) do
  {:ok, shape_sheets(data)}
rescue
  _ -> :error
end
```

El `rescue` amplio es intencional: `data` viene de la salida de un script Lua arbitrario (límite con datos no confiables), y cualquier forma no contemplada (número, string, mapa sin listas de registros, etc.) debe degradar a `:error` en vez de tumbar el `handle_event`.

## 2. `FilterLive.Form` — construir el resultado etiquetado

```elixir
def handle_event("test_run", params, socket) do
  raw_test_params = Map.get(params, "test_params", %{})
  changeset = socket.assigns.form.source
  code = get_field(changeset, :code) || ""
  params_defs = get_field(changeset, :params) || []
  output = get_field(changeset, :output)
  test_params = cast_test_params(params_defs, raw_test_params)

  result = Automator.test_run_filter(params_defs, code, test_params)

  {:noreply, assign(socket, :test_result, build_test_result(output, result))}
end

defp build_test_result(_output, {:error, reason}), do: {:error, inspect(reason)}

defp build_test_result(:xlsx, {:ok, result}) do
  case Excel.to_sheets(result) do
    {:ok, sheets} -> {:table, sheets}
    :error -> {:json_fallback, Jason.encode!(result, pretty: true)}
  end
end

defp build_test_result(_output, {:ok, result}), do: {:json, Jason.encode!(result, pretty: true)}
```

(`alias Conta.Automator.Excel` se añade junto al resto de alias del módulo.) `format_test_result/1` desaparece, sustituida por `build_test_result/2`.

## 3. `form.html.heex` — renderizado condicional

Sustituye el bloque actual (líneas 71-74):

```heex
<div :if={@test_result} class="mt-4">
  <p :if={elem(@test_result, 0) == :error} class="text-error font-semibold">{gettext("Error")}</p>
  <pre class="bg-base-200 p-4 rounded overflow-x-auto text-sm">{elem(@test_result, 1)}</pre>
</div>
```

por:

```heex
<div :if={@test_result} class="mt-4">
  <%= case @test_result do %>
    <% {:error, message} -> %>
      <p class="text-error font-semibold">{gettext("Error")}</p>
      <pre class="bg-base-200 p-4 rounded overflow-x-auto text-sm">{message}</pre>
    <% {:json, json} -> %>
      <pre class="bg-base-200 p-4 rounded overflow-x-auto text-sm">{json}</pre>
    <% {:json_fallback, json} -> %>
      <p class="text-warning text-sm mb-2">
        {gettext("The result doesn't have a table shape, showing raw JSON instead.")}
      </p>
      <pre class="bg-base-200 p-4 rounded overflow-x-auto text-sm">{json}</pre>
    <% {:table, sheets} -> %>
      <div :for={sheet <- sheets} class="mb-6 last:mb-0">
        <h4 :if={length(sheets) > 1} class="font-semibold mb-1">{sheet["name"]}</h4>
        <div class="overflow-x-auto">
          <table class="table table-zebra">
            <thead>
              <tr>
                <th :for={header <- sheet["headers"]}>{header}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- sheet["rows"]}>
                <td :for={cell <- row}>{cell}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
  <% end %>
</div>
```

Se reutiliza la clase `table table-zebra` que ya usa `<.table>` en `core_components.ex:363`, para mantener consistencia visual con el resto de la app. No se usa el componente `<.table>` en sí porque sus `:col` son slots fijos en tiempo de compilación y aquí las columnas son dinámicas (dependen del script Lua ejecutado).

`sheet["rows"]` puede contener sub-listas o mapas según lo que devolviera el script (igual que hoy consume `Excel.export/2` vía `to_list/1` antes de escribir celdas). Para que `<td :for={cell <- row}>` funcione siempre sobre una lista plana, `shape_sheets/1` ya normaliza `rows` a listas de valores en la rama de mapa de hojas (usa `get_headers/2`, que ya devuelve listas); la única rama donde `rows` podría no ser lista de listas es la de "headers/rows explícitos", donde el script Lua ya debe devolver filas como listas ordenadas según `headers` (mismo contrato que exige hoy `Excel.export/2` al hacer `row |> to_list()` antes de plantar celdas). Si una fila viniera como mapa en esa rama, `to_sheets/1` no la convierte a lista — se documenta como limitación conocida, no se soluciona aquí (fuera de alcance: no se toca el contrato de `export/2`).

## 4. Testing

- `apps/conta/test/conta/automator/excel_test.exs` (nuevo): `to_sheets/1` con las tres formas válidas (`{:ok, sheets}` con `headers`/`rows` esperados) y con formas inválidas (entero, string, lista de no-mapas) → `:error`. **Nota:** tanto `[]` como `%{}` son casos válidos que devuelven `{:ok, []}` (una hoja vacía), no `:error` — ambos caen en la rama de mapa/lista existente y `Enum.map` sobre una colección vacía simplemente no itera; se prueban explícitamente como `{:ok, []}`, no se incluyen en la lista de formas inválidas.
- `apps/conta_web/test/conta_web/live/filter_live_test.exs` (ya existe y ya tiene un test de `test_run` con `output: "json"` — este cambio lo extiende, no crea un archivo nuevo): al seleccionar `output: xlsx` y ejecutar "Run" con un script que devuelve una lista de mapas, la vista renderiza un `<table>` con los headers/rows esperados; con un script que devuelve un escalar, se muestra el aviso de fallback y el JSON.
