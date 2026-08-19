# Fuentes de datos reales para parámetros `table` en Filters/Shortcuts

## Contexto

`Conta.Automator` permite definir `Filter`/`Shortcut` con parámetros tipados (`Conta.Projector.Automator.Param`), uno de cuyos tipos es `:table`. Hoy el campo `name` de cualquier parámetro es texto completamente libre (`apps/conta_web/lib/conta_web/live/filter_live/form.html.heex:41`, `shortcut_live/form.html.heex` análogo).

En producción, dos controllers inyectan datos reales de BD en un parámetro `:table` **por convención de nombre, sin ninguna validación**:

```elixir
# apps/conta_web/lib/conta_web/controllers/expense_controller.ex:36-37
expenses = Book.list_simple_expenses_filtered(filters)
params = %{"expenses" => expenses}

# apps/conta_web/lib/conta_web/controllers/invoice_controller.ex:78-79
invoices = Book.list_invoices_filtered(filters)
params = %{"invoices" => invoices}
```

`Automator.cast/2` busca `params[param.name]`, así que un parámetro `:table` solo recibe datos reales si su `name` coincide **exactamente** con el string literal hardcodeado en el controller correspondiente ("expenses" o "invoices"). Un typo al definir el filtro falla en silencio (el parámetro queda vacío, ver `Automator.cast/2` en `apps/conta/lib/conta/automator.ex`, arreglado recientemente para devolver `[]` en vez de un string inválido).

Aparte de esos dos controllers, el filtro también puede ejecutarse vía el API JSON genérico (`apps/conta_web/lib/conta_web/api/automator/filter.ex:116`), donde el llamador aporta el valor de cualquier parámetro `:table` directamente en el body JSON — ahí no hay ninguna fuente de BD detrás, es dato arbitrario del cliente. Este documento **no** cubre ese caso: se asume que un filtro con parámetro `table` restringido al registro (ver más abajo) se ejecuta siempre vía los controllers de exportación o el panel de pruebas, no vía el API genérico con nombres arbitrarios.

## Alcance

1. Un nuevo registro único (`Conta.Automator.TableSources`) que mapea nombre de fuente → función que trae N registros reales de la BD. Inicialmente dos entradas: `"expenses"`, `"invoices"`.
2. El campo `name` de un parámetro pasa de texto libre a `<select>` restringido a las entradas del registro **cuando el tipo del parámetro es `table`**. Para el resto de tipos no cambia nada.
3. Nuevo campo `sample_limit` (entero, por parámetro) que controla cuántos registros trae el botón de carga de datos reales.
4. Botón "Cargar datos reales" en el panel "Test data" para parámetros `table`, que rellena el textarea de JSON con los N registros más recientes de la fuente elegida (sin aplicar filtros de término/año/estado — es solo una muestra para probar el script Lua).
5. Los controllers de producción (`expense_controller.ex`, `invoice_controller.ex`) dejan de usar el string literal y usan la constante que expone el registro, para que el nombre canónico viva en un único sitio.

No incluye: exponer el registro en el API JSON genérico, añadir más fuentes que expenses/invoices (el registro queda abierto a extensión futura), ni cambiar el filtrado por término/año/estado que ya existe en producción.

## 1. `Conta.Automator.TableSources`

Nuevo módulo en `apps/conta/lib/conta/automator/table_sources.ex`:

```elixir
defmodule Conta.Automator.TableSources do
  alias Conta.Book

  @sources %{
    "expenses" => %{label: "Expenses", sample: fn limit -> Book.list_simple_expenses_filtered([], limit) end},
    "invoices" => %{label: "Invoices", sample: fn limit -> Book.list_invoices_filtered([], limit) end}
  }

  @default_sample_limit 5

  def default_sample_limit, do: @default_sample_limit

  @spec names() :: [String.t()]
  def names, do: Map.keys(@sources)

  @spec options() :: [{String.t(), String.t()}]
  def options, do: Enum.map(@sources, fn {name, %{label: label}} -> {label, name} end)

  @spec known?(String.t()) :: boolean()
  def known?(name), do: Map.has_key?(@sources, name)

  @spec sample(String.t(), pos_integer()) :: [map()] | {:error, :unknown_source}
  def sample(name, limit) do
    case @sources[name] do
      %{sample: fun} -> fun.(limit)
      nil -> {:error, :unknown_source}
    end
  end
end
```

`Book.list_invoices_filtered/1` no soporta límite hoy; se le añade un segundo argumento **posicional** `limit \\ :infinity` (misma convención que `list_simple_expenses_filtered/3`, `apps/conta/lib/conta/book.ex:83`, no un keyword-list de opciones), quedando `list_invoices_filtered(filters, limit \\ :infinity)`. Internamente reutiliza `Ecto.Query.limit/3` cuando el valor no es `:infinity`, igual que hace `list_simple_expenses_query/2` (`book.ex:95` y siguientes) para expenses.

Tests unitarios (`apps/conta/test/conta/automator/table_sources_test.exs`): `names/0` y `options/0` devuelven las dos fuentes; `known?/1` true/false; `sample/2` con una fixture de expense/invoice insertada en BD, comprobando que respeta el límite.

## 2. Campo `sample_limit` en `Param`

Se añade `field :sample_limit, :integer` a los cinco embedded schemas que representan un `Param` a lo largo del pipeline comando → evento → proyector:

- `Conta.Command.SetFilter.Param` (`apps/conta/lib/conta/command/set_filter.ex:14-18`)
- `Conta.Command.SetShortcut.Param` (`apps/conta/lib/conta/command/set_shortcut.ex:12-16`)
- `Conta.Event.FilterSet.Param` (`apps/conta/lib/conta/event/filter_set.ex:16-20`)
- `Conta.Event.ShortcutSet.Param` (`apps/conta/lib/conta/event/shortcut_set.ex`, mismo patrón)
- `Conta.Projector.Automator.Param` (`apps/conta/lib/conta/projector/automator/param.ex`)

Se añade a `@optional_fields` en cada `changeset_params/2` correspondiente (solo relevante cuando `type == :table`; no se valida como requerido para los demás tipos). No hace falta migración de BD: `params` se persiste como una sola columna `jsonb` (ver `apps/conta/priv/repo/migrations/20240627145305_create_automator_filters.exs:11`).

**Propagación automática:** `Conta.Aggregate.Automator.execute/2` (comando → evento) y `Conta.Projector.Automator` (evento → proyección) convierten cada `Param` con `Map.from_struct/1` genérico (`apps/conta/lib/conta/aggregate/automator.ex:32-34` y `apps/conta/lib/conta/projector/automator.ex:24`), así que el campo nuevo viaja solo una vez declarado en los schemas — no hay listas de campos explícitas que tocar ahí.

**Conversión manual necesaria** (cuatro sitios que seleccionan campos de `Param` a mano en vez de propagarlos genéricamente; hay que añadir `sample_limit` en cada uno):

- `get_set_filter/1` (`apps/conta/lib/conta/automator.ex`, línea ~107): `Projector.Param` → `SetFilter.Param`
- `get_set_shortcut/1` (línea ~83): `Projector.Param` → `SetShortcut.Param`
- `to_projector_params/1` (línea ~167): `Command.Param` (Filter o Shortcut) → `Projector.Param`, usado por `test_run_filter/3` y `test_run_shortcut/3`
- `@derive {Jason.Encoder, only: ~w[name type options]a}` en `Conta.Projector.Automator.Param` (`apps/conta/lib/conta/projector/automator/param.ex:7`): es un allowlist explícito de campos a serializar. `ContaWeb.Api.Automator.Filter.show/2` y `Shortcut.show/2` (`apps/conta_web/lib/conta_web/api/automator/filter.ex:32-34`, `.../shortcut.ex:35-37`) codifican el struct completo a JSON, que recorre esta lista para cada `Param` anidado. Si no se añade `sample_limit` a este `only:`, el API JSON de detalle de filter/shortcut lo omitirá en silencio aunque el resto del pipeline sí lo lleve.

## 3. Formulario de definición del parámetro

En `filter_live/form.html.heex:39-48` y el equivalente de `shortcut_live/form.html.heex`, la fila de cada parámetro cambia según `p[:type].value`:

```heex
<.inputs_for :let={p} field={@form[:params]}>
  <div class="grid grid-cols-[1fr_1fr_1fr_1fr_auto] gap-2 items-end mb-2">
    <%= if Phoenix.HTML.Form.input_value(p, :type) == :table do %>
      <.input field={p[:name]} type="select" label={gettext("Name")} options={TableSources.options()} />
      <.input field={p[:sample_limit]} type="number" label={gettext("Sample size")} value={p[:sample_limit].value || TableSources.default_sample_limit()} />
    <% else %>
      <.input field={p[:name]} label={gettext("Name")} />
      <.input field={p[:options]} label={gettext("Options (comma separated)")} />
    <% end %>
    <.input field={p[:type]} type="select" label={gettext("Type")} options={param_type_options()} />
    <.button type="button" phx-click="del_param" phx-value-index={p.index} class="btn-sm btn-error">
      {gettext("Remove")}
    </.button>
  </div>
</.inputs_for>
```

El `phx-change="validate"` ya existente en el formulario recalcula el changeset en cada cambio (incluido el `<select>` de tipo), así que cambiar de "table" a otro tipo y viceversa re-renderiza la fila correcta sin JS adicional — mismo patrón que ya usa la app para reaccionar a cambios de formulario.

Nota de diseño: al restringir `name` al registro cuando el tipo es `table`, si alguien cambia el tipo de un parámetro existente de `table` a otro tipo y vuelve a `table`, `name` puede quedar con un valor que ya no está en las opciones del `<select>` (p. ej. si antes era texto libre de una versión previa a este cambio). Se acepta este caso borde: el `<select>` simplemente no preseleccionará nada hasta que el usuario elija explícitamente una fuente válida; `validate_params/2` ya rechaza nombres que no estén entre los parámetros declarados via el mecanismo existente.

## 4. Botón "Cargar datos reales" en Test data

En `ContaWeb.AutomatorComponents.test_param_input/1` (`apps/conta_web/lib/conta_web/components/automator_components.ex:61-72`), la rama `render_control` para `:table` (línea 114-123) añade el botón junto al textarea:

```elixir
defp render_control(%{param: %{type: :table}} = assigns) do
  ~H"""
  <div class="flex gap-2 items-start">
    <textarea
      id={@id}
      name={"test_params[#{@param.name}]"}
      class="w-full textarea textarea-bordered"
      rows="3"
    ></textarea>
    <.button
      type="button"
      phx-click="load_table_sample"
      phx-value-param={@param.name}
      class="btn-sm"
    >
      {gettext("Load real data")}
    </.button>
  </div>
  """
end
```

Nuevo `handle_event("load_table_sample", %{"param" => name}, socket)` en `FilterLive.Form` y `ShortcutLive.Form`:

```elixir
def handle_event("load_table_sample", %{"param" => name}, socket) do
  param = Enum.find(socket.assigns.params_defs, &(&1.name == name))
  limit = param.sample_limit || TableSources.default_sample_limit()

  case TableSources.sample(name, limit) do
    {:error, :unknown_source} ->
      # Caso borde de la nota en la sección 3: un `name` que ya no está en el
      # registro (p. ej. quedó de antes de este cambio). No hay nada que cargar.
      {:noreply, put_flash(socket, :error, gettext("Unknown data source"))}

    sample ->
      json = Jason.encode!(sample, pretty: true)

      form_params =
        Map.update(socket.assigns.form_params, "test_params", %{name => json}, &Map.put(&1, name, json))

      {:noreply, assign(socket, :form_params, form_params)}
  end
end
```

El textarea del parámetro `table` es un input de formulario normal (`name="test_params[...]"`), no tiene `phx-update="ignore"`, así que basta con que el `value` derive de `@form_params["test_params"][name]` para que LiveView lo re-renderice con el JSON cargado — igual que ya ocurre con cualquier otro campo controlado del formulario. El usuario puede seguir editando el JSON a mano antes de pulsar "Run".

*(Nota de implementación: hoy `test_param_input`/`render_control` no leen `@form_params` para fijar el `value` del textarea — habrá que añadir ese `value={...}` explícito, ya que actualmente el textarea siempre nace vacío en cada render. Se revisa en la fase de plan.)*

## 5. Controllers de producción

`expense_controller.ex:37` y `invoice_controller.ex:79` cambian el string literal por la clave del registro:

```elixir
# antes
params = %{"expenses" => expenses}
# después
params = %{TableSources.expenses_key() => expenses}
```

Se añaden `TableSources.expenses_key/0` y `TableSources.invoices_key/0`, cada una devolviendo el string literal correspondiente (`"expenses"`/`"invoices"`) como única fuente de verdad de esa clave — son claves de dominio estables, no dependen del orden de `@sources`. El query con filtros de término/año/estado no cambia; solo cambia de dónde sale el nombre de la clave.

## 6. Testing

- `Conta.Automator.TableSources` (unitarios): registro, `sample/2` con datos reales insertados vía fixtures.
- `Automator.cast/2` / `Automator.get_set_filter/1` / `get_set_shortcut/1` / `to_projector_params/1`: el campo `sample_limit` viaja correctamente por el pipeline completo (comando ↔ proyector).
- API JSON (`ContaWeb.Api.Automator.Filter.show/2` / `Shortcut.show/2`): la respuesta de detalle incluye `sample_limit` en cada `Param` de tipo `table` — regresión directa del `@derive Jason.Encoder` de la sección 2 si se olvida actualizar el `only:`.
- `Book.list_invoices_filtered/2`: nuevo argumento `limit` respetado.
- LiveView (`Phoenix.LiveViewTest`) para `FilterLive.Form`/`ShortcutLive.Form`: el botón "Cargar datos reales" rellena el textarea con el JSON esperado; el `<select>` de `name` para tipo `table` solo ofrece las fuentes del registro.
- Regresión: `ExpenseController.run/2` e `InvoiceController.run/2` siguen sirviendo el archivo esperado con la nueva clave (mismo comportamiento observable).
