# CSV en el panel de pruebas del editor de Importers

## Contexto

Un Importer transforma datos de entrada (un CSV) en comandos que insertan
transacciones en cuentas del ledger. Esto ya funciona en producción:
`ContaWeb.ReconciliationLive.Upload` (`apps/conta_web/lib/conta_web/live/reconciliation_live/upload.ex`)
sube un extracto bancario `.csv`, lo parsea con `Conta.Reconciliation.CsvImport.parse/1`
(`apps/conta/lib/conta/reconciliation/csv_import.ex`) a una lista de mapas, y
llama a `Conta.Automator.run_importer/4` (`apps/conta/lib/conta/automator.ex:276-304`),
que ejecuta el script Lua del importer y despacha `ImportMovements`.

El propio editor del importer (`ContaWeb.ImporterLive.Form`,
`apps/conta_web/lib/conta_web/live/importer_live/form.ex`) tiene un panel
"Test data" que ejecuta el mismo script Lua sin despachar comandos reales
(`handle_event("test_run", ...)`, líneas 76-85). El único parámetro del
importer, `movements` (tipo `:table`, fijo — a diferencia de Filter/Shortcut,
que tienen params configurables por el usuario), se introduce hoy como un
`<textarea>` genérico (`AutomatorComponents.render_control/1`, cláusula
`:table`, `apps/conta_web/lib/conta_web/components/automator_components.ex:133-142`)
donde hay que escribir el JSON a mano. `Automator.test_run_importer/2`
(`automator.ex:233-245`) decodifica ese texto como JSON a través de la rama
`:table` de `cast/3` (`automator.ex:469-491`).

Probar un importer pensado para consumir CSV escribiendo JSON a mano es
artificial y no refleja el dato real con el que se va a ejecutar en
producción. Este documento cubre que el panel de pruebas acepte CSV
directamente — pegado en el textarea o cargado desde un fichero — igual que
el flujo real.

## Alcance

1. El control de `movements` en el panel de pruebas de `ImporterLive.Form`
   pasa de esperar JSON a esperar CSV (mismo formato que `CsvImport.parse/1`).
   No cambia la firma de `Automator.test_run_importer/2`: ya acepta listas
   ya decodificadas a través de la rama `other -> to_list(other)` de `cast/3`.
2. Un nuevo hook de JS permite elegir un fichero `.csv` y vuelca su
   contenido tal cual en el textarea, en el cliente, sin pasar por el
   servidor (no se usa `allow_upload` — el textarea sigue siendo la única
   fuente de verdad al enviar "Run").
3. `error_message/1`, hoy privado a `ReconciliationLive.Upload`
   (`upload.ex:60-67`), se extrae a un módulo nuevo en `conta_web` y lo
   usan ambas vistas (no a `Conta.Reconciliation.CsvImport`, que vive en
   `apps/conta` — ver justificación en la sección 1).
4. Como `Conta.Reconciliation.CsvImport` fija el separador a `,` y el
   escape a `"` (`NimbleCSV.define(Parser, separator: ",", escape: "\"")`,
   `csv_import.ex:7`), ambos puntos de entrada de CSV (panel de pruebas del
   importer y subida real de extractos) añaden un texto de ayuda
   indicándolo — hoy ninguno de los dos lo explica, y un CSV con `;` (común
   en exportaciones en español) falla hoy con un mensaje de columna que no
   indica la causa.
5. Dejar el textarea de `movements` en blanco y pulsar "Run" sigue
   probando contra una tabla vacía (`[]`), sin error — igual que el
   comportamiento actual con JSON en blanco.
6. No cambia el flujo real de `ReconciliationLive.Upload` (sigue con
   `allow_upload` server-side) más allá de reusar `error_message/1` y el
   nuevo texto de ayuda.

## 1. `ContaWeb.CsvImportMessages` (nuevo) — `error_message/1`

**Por qué no vive en `Conta.Reconciliation.CsvImport`:** ese módulo está en
`apps/conta`, que no depende de `apps/conta_web`
(`apps/conta/mix.exs` no tiene `{:conta_web, in_umbrella: true}` — es
`conta_web` quien depende de `conta`, no al revés). Un `use Gettext,
backend: ContaWeb.Gettext` ahí introduciría una dependencia inversa e
inexistente (`ContaWeb.Gettext` no estaría compilado/disponible al
compilar `conta`) y rompería el build. Todo el uso de `gettext` en el
proyecto está hoy confinado a `apps/conta_web` — se mantiene así.

En su lugar, se crea `apps/conta_web/lib/conta_web/csv_import_messages.ex`,
con el mismo contenido que hoy tiene `error_message/1` en `upload.ex:60-67`
(movido tal cual, mismo comentario sobre por qué es pública):

```elixir
defmodule ContaWeb.CsvImportMessages do
  @moduledoc """
  User-facing messages for `Conta.Reconciliation.CsvImport.parse/1` error
  results, shared by every conta_web view that accepts CSV input
  (ReconciliationLive.Upload's real bank-statement upload, ImporterLive.Form's
  CSV test-data panel).
  """
  use Gettext, backend: ContaWeb.Gettext

  @doc false
  # Public (rather than private) so it can be unit-tested directly: the
  # `:empty_file` case corresponds to a zero-byte upload, which
  # Phoenix.LiveViewTest's chunked-upload simulator (as of phoenix_live_view
  # 1.1.27) cannot itself reproduce — its UploadClient.progress_stats/2
  # divides by the entry's byte size, which raises ArithmeticError for a
  # genuinely empty file.
  def error_message([]), do: gettext("Please choose a file to upload")
  def error_message({:error, :empty_file}), do: gettext("The CSV data is empty")

  def error_message({:error, {:column_mismatch, line}}) do
    gettext("Row %{line} has a different number of columns than the header", line: line)
  end

  def error_message({:error, reason}), do: inspect(reason)
end
```

Cambio respecto al original: el mensaje de `:empty_file` pasa de "The
uploaded file is empty" a "The CSV data is empty", porque ahora también
cubre un textarea vacío, no solo un fichero subido. El caso `[]` (lista de
entries vacía — nadie eligió fichero) sigue existiendo para
`ReconciliationLive.Upload`; `ImporterLive.Form` nunca produce ese valor
porque su blank case se resuelve como `{:ok, []}` antes de llegar a
`CsvImport.parse/1` (ver sección 2).

`ReconciliationLive.Upload` (`upload.ex`) borra su `error_message/1` local
(líneas 52-67), añade `alias ContaWeb.CsvImportMessages`, y su llamada en
`handle_event("save", ...)` (línea 48) pasa de `error_message(reason)` a
`CsvImportMessages.error_message(reason)`. `Conta.Reconciliation.CsvImport`
(en `apps/conta`) no cambia — sigue devolviendo únicamente `{:ok, rows}` /
`{:error, reason}` sin texto localizado.

## 2. `ImporterLive.Form` — el panel de pruebas pasa a CSV

`apps/conta_web/lib/conta_web/live/importer_live/form.ex`:

- `alias Conta.Reconciliation.CsvImport` y
  `alias ContaWeb.CsvImportMessages` se añaden junto al resto de alias.
- `mount/3` deja de asignar `:movements_param` (línea 24) — ya no se usa
  `<.test_param_input>` para este campo (ver sección 3). El módulo
  attribute `@movements_param` (líneas 14-17) y el
  `alias Conta.Projector.Automator.Param` del que depende (línea 12) se
  eliminan por completo — no se usan en ningún otro sitio del módulo
  (verificado: `Param` solo aparece en esas dos líneas), y dejarlos
  produciría un warning de compilación por atributo/alias sin uso.
- `handle_event("test_run", ...)` cambia de decodificar JSON a parsear CSV:

```elixir
def handle_event("test_run", params, socket) do
  raw_test_params = Map.get(params, "test_params", %{})
  changeset = socket.assigns.form.source
  code = get_field(changeset, :code) || ""
  csv_text = raw_test_params["movements"] || ""

  result =
    case parse_movements_csv(csv_text) do
      {:ok, rows} -> Automator.test_run_importer(code, rows)
      {:error, reason} -> {:error, CsvImportMessages.error_message(reason)}
    end

  {:noreply, assign(socket, :test_result, format_test_result(result))}
end

defp parse_movements_csv(csv_text) do
  if String.trim(csv_text) == "" do
    {:ok, []}
  else
    CsvImport.parse(csv_text)
  end
end
```

`format_test_result/1` no cambia: su cláusula
`{:error, reason} when is_binary(reason)` ya cubre el mensaje devuelto por
`CsvImportMessages.error_message/1` sin envolverlo en `inspect/1`.

`Automator.test_run_importer/2` (`automator.ex:233-245`) no cambia: recibe
`rows` (lista de mapas) en vez de un binario JSON, y su `cast/3` ya sabe
tratar ese caso (`automator.ex:486-487`, rama `other -> to_list(other)`).

## 3. `form.html.heex` — fichero + textarea + ayuda de formato

Sustituye (línea 35):

```heex
<.test_param_input param={@movements_param} />
```

por:

```heex
<div class="fieldset mb-2">
  <label for="test_params_movements">
    <span class="label mb-1">{gettext("movements (CSV)")}</span>
  </label>
  <input
    type="file"
    accept=".csv"
    id="movements-csv-file"
    phx-hook="CsvFileInput"
    data-target="test_params_movements"
    class="file-input file-input-bordered w-full mb-2"
  />
  <textarea
    id="test_params_movements"
    name="test_params[movements]"
    class="w-full textarea textarea-bordered font-mono text-sm"
    rows="6"
  ></textarea>
  <p class="text-sm opacity-70 mt-1">
    {gettext("Comma-separated CSV, double quotes (\") to escape values containing commas or newlines.")}
  </p>
</div>
```

Se mantiene `id="test_params_movements"` / `name="test_params[movements]"`
(el mismo que generaba `test_param_input` para este param) para no romper
tests existentes que dependan de ese id, y porque `handle_event("test_run",
...)` sigue leyendo `params["test_params"]["movements"]` con la misma
forma. No lleva `phx-update="ignore"`: nada en `ImporterLive.Form` fuerza un
re-render de este textarea tras el mount (no recibe `value` de un assign),
así que no hay conflicto entre el DOM tocado por el hook y el diffing de
LiveView.

## 4. Hook `CsvFileInput`

`apps/conta_web/assets/js/hooks/csv_file_input.js` (nuevo), mismo patrón que
`monaco_editor.js` (objeto con `mounted()`, `export default` al final):

```js
const CsvFileInput = {
  mounted() {
    this.el.addEventListener("change", (event) => {
      const file = event.target.files[0];
      if (!file) return;

      const target = document.getElementById(this.el.dataset.target);
      if (!target) {
        console.error("CsvFileInput hook: could not find target textarea", this.el.dataset.target);
        return;
      }

      const reader = new FileReader();
      reader.onload = () => {
        target.value = reader.result;
      };
      reader.readAsText(file);
    });
  },
};

export default CsvFileInput;
```

`apps/conta_web/assets/js/hooks/index.js`:

```js
import MonacoEditor from "./monaco_editor";
import CsvFileInput from "./csv_file_input";

export default {
  MonacoEditor,
  CsvFileInput,
};
```

No se dispara ningún evento sintético tras rellenar el textarea: el submit
del panel de pruebas es `phx-submit="test_run"` puro (no hay `phx-change`
escuchando este campo), así que no hace falta más que fijar `.value`.

## 5. `ReconciliationLive.Upload` — mismo texto de ayuda

`apps/conta_web/lib/conta_web/live/reconciliation_live/upload.html.heex`,
justo debajo del `<.input type="file" ... />` (línea 16):

```heex
<p class="text-sm opacity-70 mt-1">
  {gettext("Comma-separated CSV, double quotes (\") to escape values containing commas or newlines.")}
</p>
```

Mismo string que en el panel del importer (sección 3), para que `gettext`
comparta la traducción.

## 6. Testing

- `apps/conta_web/test/conta_web/csv_import_messages_test.exs` (nuevo):
  cobertura directa de `ContaWeb.CsvImportMessages.error_message/1` — hoy
  esos casos viven indirectamente en `upload_test.exs`; se mueven a este
  archivo (`[]` → "Please choose a file to upload", `{:error, :empty_file}`
  → "The CSV data is empty", `{:error, {:column_mismatch, 3}}` → mensaje
  con línea 3).
- `apps/conta_web/test/conta_web/live/reconciliation_live/upload_test.exs`:
  se retiran los tests movidos a `csv_import_messages_test.exs`; el resto
  no cambia de comportamiento.
- `apps/conta_web/test/conta_web/live/importer_live_test.exs`: se
  actualiza/añade el test de `test_run` para enviar CSV en vez de JSON en
  `test_params[movements]`; se añaden casos para CSV mal formado (mensaje
  de columna) y para textarea en blanco (sigue probando contra `[]`, sin
  error).
- El hook `CsvFileInput` no tiene test automatizado — no existe arnés de
  test de JS en el proyecto (comprobado: no hay `*.test.js` ni `*spec.js`
  fuera de `node_modules`), igual que `MonacoEditor`.
- Los dos strings nuevos de `gettext(...)` (`"movements (CSV)"` y el texto
  de ayuda de separador/escape) necesitan un `mix gettext.extract` /
  `gettext.merge` para llegar a los `.po` — paso rutinario, se menciona
  aquí para no olvidarlo durante la implementación.
