# Editor Monaco para código Lua de Filters y Shortcuts

## Contexto

Hoy `Conta.Automator` gestiona `Filter` y `Shortcut`, cada uno con un campo `code` (texto Lua ejecutado vía Luerl) y una lista tipada de `params`. La única interfaz existente es una API JSON (`ContaWeb.Api.Automator.Filter`/`Shortcut`) con CRUD + `run`. No existe ninguna LiveView para gestionarlos ni forma de probar el código antes de guardarlo.

Este documento diseña una interfaz web (LiveView) que permite crear/editar filters y shortcuts con un editor de código Monaco (como VSCode), definir datos de prueba y ejecutar el código contra esos datos para ver el resultado, antes de guardar mediante el comando correspondiente (`SetFilter`/`SetShortcut`).

## Alcance

Incluye construir el CRUD completo (listado, crear, editar, borrar) para Filters y Shortcuts, ya que no existe ninguna pantalla previa. El campo `language` se fija siempre a `:lua` en la UI (oculto), dado que `Automator.run/2` hoy solo soporta ejecutar Lua (PHP rompe con `FunctionClauseError`). Por la misma razón, el campo `automator` también se fija de forma oculta al valor constante `"automator"` (igual que hace hoy `@default_automator` en `ContaWeb.Api.Automator.Filter`/`Shortcut`) — no es una entidad multi-tenant configurable desde esta UI.

## 1. Backend: funciones de "test run"

Se añaden dos funciones públicas a `Conta.Automator`, sin modificar `run_filter/3` ni `run_shortcut/3` (que siguen sirviendo a la API JSON sobre registros ya persistidos):

```elixir
@spec test_run_filter([Param.t() | SetFilter.Param.t()], String.t(), map()) ::
        {:ok, term()} | {:error, term()}
def test_run_filter(params_defs, code, test_params)

@spec test_run_shortcut([Param.t() | SetShortcut.Param.t()], String.t(), map()) ::
        {:ok, [map()]} | {:error, term()}
def test_run_shortcut(params_defs, code, test_params)
```

Comportamiento:
- Normalizan `params_defs` (que en el formulario son `SetFilter.Param`/`SetShortcut.Param` embebidos, o mapas planos si vienen del form params) a `%Conta.Projector.Automator.Param{}`, reutilizando así, sin duplicar, la lógica privada existente `validate_params/2` y `cast/3`.
- Ejecutan `Conta.Automator.Lua.run/2` directamente con los params casteados.
- `test_run_filter/3` devuelve el resultado decodificado tal cual (se muestra siempre como JSON en el panel de pruebas, independientemente del `output` configurado — no tiene sentido previsualizar un binario xlsx en pantalla).
- `test_run_shortcut/3` valida que el retorno tenga la forma `%{"status" => "ok", "commands" => commands}` (igual que `run_shortcut/3`), pero **nunca despacha los comandos** — los devuelve para mostrarlos. Si la forma no es correcta, devuelve `{:error, {:invalid_code_return, return}}` igual que hoy.

## 2. Rutas y páginas

Nuevas LiveViews, montadas en una nueva sección de menú "Automatización":

- `ContaWeb.FilterLive.Index` → `/automation/filters` (listado, borrar, enlaces a nuevo/editar)
- `ContaWeb.FilterLive.Form` → `/automation/filters/new` y `/automation/filters/:id/edit` (página completa, no modal)
- `ContaWeb.ShortcutLive.Index` → `/automation/shortcuts`
- `ContaWeb.ShortcutLive.Form` → `/automation/shortcuts/new` y `/automation/shortcuts/:id/edit`

Los formularios de Filter y Shortcut comparten un componente de "datos generales" + el bloque de editor Monaco + panel de pruebas (parametrizado por `kind: :filter | :shortcut`), ya que ambos esquemas son casi idénticos (`Filter` añade `type` y `output`).

En `apps/conta_web/lib/conta_web/components/layouts/app.html.heex` se añade un `<.navbar_dropdown name={gettext("Automation")}>` con items "Filters" y "Shortcuts", siguiendo el mismo patrón que "Ledger"/"Books"/"Directories".

Las rutas van en `apps/conta_web/lib/conta_web/router.ex`, dentro del bloque `live_session :require_authenticated_user` existente (el mismo que ya contiene `InvoiceLive`, `AccountLive`, `ContactLive`, etc.), como un nuevo `scope "/automation/filters/"` y `scope "/automation/shortcuts/"` siguiendo el mismo patrón `live "/"`, `live "/new"`, `live "/:id/edit"`.

## 3. Integración de Monaco

El proyecto no usa npm para el resto de los assets (esbuild/tailwind vía Mix, JS vendorizado a mano en `assets/vendor/`). Para Monaco:

- Se añade `apps/conta_web/assets/package.json` con `monaco-editor` como única dependencia de npm, instalada vía `npm install --prefix assets` — el mecanismo que ya sugiere el comentario existente en `assets/js/app.js`. Se agrega ese paso al alias `assets.setup` en `apps/conta_web/mix.exs`, junto a `tailwind.install --if-missing` / `esbuild.install --if-missing`.
- esbuild resuelve módulos de `node_modules` sin configuración adicional (usa `NODE_PATH` ya apuntando a `deps`, y resolución relativa estándar desde `assets/`), así que `import * as monaco from "monaco-editor"` funciona directo desde el hook JS.
- Monaco incluye tokenizer básico de Lua de fábrica (resaltado de sintaxis) sin necesitar web workers de lenguaje (esos son solo para TS/JSON/CSS). Puede aparecer un warning en consola por el worker por defecto ausente; no es bloqueante para edición simple. Se documenta como limitación conocida.
- Nuevo hook LiveView `MonacoEditor` en `apps/conta_web/assets/js/hooks/monaco_editor.js`:
  - `mounted()`: crea el editor sobre un `<div>`, `language: "lua"`, tema acorde al modo oscuro/claro actual de la app (usa el mismo mecanismo que `daisyui-theme.js`), valor inicial tomado del input oculto asociado.
  - En cada cambio de contenido (debounce ~300ms): copia el valor al input oculto (`@form[:code]`) y dispara un evento `input` nativo sobre él, para que el `phx-change="validate"` ya existente del formulario lo capture — no se necesita un evento de servidor a medida para tipear.
  - El contenedor del editor usa `phx-update="ignore"` para que LiveView no lo toque entre renders.
  - `destroyed()`: destruye la instancia de Monaco al desmontar, para evitar fugas de memoria al navegar.
- `apps/conta_web/assets/js/app.js` pasa a registrar `hooks: Hooks` en el `LiveSocket` (hoy no tiene ninguno definido).

## 4. Panel de datos de prueba y ejecución

- El formulario mantiene el `changeset` normal (`name`, `description`, `params`, `code`, etc.) para "Guardar", igual que el patrón de `entry_live/form_component.ex`.
- Aparte, el LiveView mantiene un assign efímero `:test_params` (no forma parte del changeset) y `:test_result`.
- Debajo del editor Monaco, un mini-formulario generado dinámicamente a partir de la lista **actual** de `params` del changeset (aunque el filter/shortcut no se haya guardado todavía), mapeando cada `Param.type` a un control:
  - `string` → texto · `date` → date picker · `integer`/`money` → number · `currency` → select con `Money.Currency.all()` · `options` → select con `param.options` · `account_name` → texto (ruta con puntos) · `table` → textarea con JSON.
- Botón **"Ejecutar"** (`phx-submit="test_run"` en ese mini-form) invoca `Automator.test_run_filter/3` o `test_run_shortcut/3` con el código y los params **actuales del editor**, sin necesidad de guardar antes.
- El resultado se muestra en un bloque `<pre>` de solo lectura:
  - Filter: el JSON que devolvería la Lua.
  - Shortcut: la lista de `commands` que se generarían, dejando explícito en la UI que no se despachan de verdad.
  - Errores de Lua se muestran igual, resaltados como error.
- "Guardar" es una acción de formulario independiente y separada de "Ejecutar".

## 5. Manejo de errores

- Errores de changeset (nombre duplicado, campos requeridos) se muestran igual que en `entry_live` (mensajes bajo cada campo).
- Errores de ejecución Lua (sintaxis, runtime) se muestran en el panel de resultado; no bloquean el guardado — se puede guardar código con errores, igual que permite la API hoy (no hay validación de sintaxis Lua al persistir).
- Si el shortcut no devuelve el formato `{"status" => "ok", "commands" => [...]}`, se muestra el error `:invalid_code_return` de forma legible.

## 6. Plan de pruebas

- Tests ExUnit para `Automator.test_run_filter/3` y `test_run_shortcut/3`: éxito, params inválidos, error de sintaxis/runtime Lua, shortcut con formato de retorno incorrecto. Se apoyan en los fixtures existentes (`apps/conta/test/support/fixtures/automator_fixtures.ex`).
- Tests `Phoenix.LiveViewTest` para `FilterLive`/`ShortcutLive` (Index y Form): crear, editar, borrar, y disparar `test_run` verificando que **no se despacha ningún comando real** (sin efectos en `Book`/`Ledger`).
- Verificación manual en navegador (fuera de ExUnit): abrir `/automation/filters/new`, escribir código en Monaco, ejecutar con datos de prueba, guardar, y confirmar vía `GET /api/v1/automator/filters` que el `code` persistido es el esperado.

## Fuera de alcance

- Ejecutar shortcuts de verdad (con dispatch real) desde el editor.
- Soporte de PHP como lenguaje alternativo.
- Autocompletado/IntelliSense avanzado de Lua (solo resaltado de sintaxis básico incluido en Monaco).
- Migrar el resto de los assets del proyecto a un pipeline npm; el `package.json` introducido es exclusivo para vendorizar `monaco-editor`.
