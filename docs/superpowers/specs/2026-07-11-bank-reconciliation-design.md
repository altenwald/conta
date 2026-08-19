# Conciliación bancaria — Diseño

Fecha: 2026-07-11

## Objetivo

Permitir importar extractos bancarios (CSV, en esta primera versión) a través de
"importadores" definidos en Lua (análogos a los Shortcuts de Automation), cotejarlos
automáticamente contra un conjunto de reglas de concordancia (matches) para proponer
la cuenta contrapartida del ledger, y confirmarlos uno a uno o en bloque para
convertirlos en transacciones reales del ledger.

## Contexto existente relevante

- **Automation / Shortcuts**: `apps/conta/lib/conta/aggregate/automator.ex`,
  `apps/conta/lib/conta/automator.ex`, `apps/conta/lib/conta/projector/automator/{shortcut,param}.ex`,
  `apps/conta_web/lib/conta_web/live/shortcut_live/`. Los shortcuts ejecutan código Lua
  (vía `:luerl`, `apps/conta/lib/conta/automator/lua.ex`) contra parámetros tipados,
  incluido un tipo `:table` que acepta listas/mapas o JSON. El resultado esperado es
  `%{"status" => "ok", "commands" => [...]}`; `Conta.Automator.process_result/2`
  (automator.ex:231-269) despacha un comando distinto según `"type"` (hoy: `"transaction"`
  → `SetAccountTransaction`, `"invoice"` → `SetInvoice`).
- **CQRS/Commanded**: `apps/conta/lib/conta/commanded/router.ex` registra
  `identify(Aggregate, by: :clave)` + `dispatch(Command, to: Aggregate)`. Los aggregates
  existentes (`Ledger`, `Automator`, `Company`) son singletons con un único id fijo.
  No existen Process Managers (`Commanded.ProcessManagers.ProcessManager`) en el código;
  toda orquestación multi-comando ocurre de forma síncrona en capa de contexto/LiveView.
- **Transacciones**: `Conta.Command.SetAccountTransaction` (entries con `account_name`,
  `debit`/`credit`), validado y aplicado en `apps/conta/lib/conta/aggregate/ledger.ex:137-180`.
- **Cuentas**: tipos `~w[assets liabilities equity revenue expenses]a`
  (`apps/conta/lib/conta/aggregate/ledger/account.ex:7`), direccionadas por `account_name`
  (lista de segmentos).
- **Sin infraestructura de importación existente**: no hay `NimbleCSV` ni lectura de
  Excel en el proyecto; `elixlsx` solo exporta.

## Alcance de esta primera versión

- Formato de fichero soportado: **CSV** únicamente (vía `NimbleCSV`). Excel queda fuera
  de esta versión.
- Deduplicación de movimientos entre subidas: **no** se implementa en esta versión; el
  usuario gestiona duplicados manualmente desde la pantalla de revisión.
- Reglas de concordancia: **globales** (no restringidas a una cuenta assets concreta).

## Arquitectura

### Aggregate `Reconciliation` (singleton)

Nuevo aggregate, mismo patrón que `Automator`/`Ledger`
(`identify(Reconciliation, by: :reconciliation)`, id fijo). Mantiene en su estado:

- Lista **ordenada** de reglas de concordancia (match rules).
- Todos los movimientos temporales pendientes, de cualquier importación/cuenta assets,
  hasta que se confirman (se transforman en transacción) o se eliminan.

Comandos y eventos:

| Comando | Evento | Descripción |
|---|---|---|
| `SetMatchRule` | `MatchRuleSet` | Crea o actualiza una regla (upsert por `id`) |
| `RemoveMatchRule` | `MatchRuleRemoved` | Elimina una regla |
| `ReorderMatchRules` | `MatchRulesReordered` | Cambia el orden de evaluación |
| `ImportMovements` | `MovementsImported` | Añade N movimientos nuevos; el aggregate evalúa las reglas sobre cada uno y anota `account_name` propuesto (o lo deja `nil`) |
| `UpdateMovement` | `MovementUpdated` | Edición manual de un movimiento pendiente (cuenta, importe, descripción, fecha) |
| `RemoveMovement` | `MovementRemoved` | Elimina un movimiento sin generar transacción |
| `MarkMovementTransacted` | `MovementTransacted` | Marca internamente que ya se creó la transacción del ledger para este movimiento (ver "Confirmación") |

No existe comando de "confirmar" dentro del aggregate — confirmar es una operación de
capa de contexto que combina dos aggregates (ver más abajo), no una transición de
estado unilateral del aggregate `Reconciliation`.

**Reevaluación de reglas al editar un movimiento**: si `UpdateMovement` cambia
`amount`, `on_date` o `description` **y el movimiento tiene actualmente
`account_name = nil`**, el aggregate evalúa las reglas de match contra los valores
nuevos (mismo mecanismo que usa `ImportMovements`) y asigna `account_name` si alguna
hace match. Si el movimiento ya tiene una `account_name` asignada (por match anterior
o por asignación manual), **nunca se re-evalúa ni se sobrescribe** al editar otros
campos — solo se sobrescribe cuando la propia edición cambia `account_name`
directamente. Esta regla única (en vez de distinguir "vino de un match" vs. "fue
asignación manual") evita que una edición sin relación (p.ej. corregir una errata en la
descripción) pueda pisar una cuenta ya asignada, y no depende de qué campos concretos
venga en la misma petición de edición.

### Confirmación (orquestación en capa de contexto, no en el aggregate)

Un aggregate de Commanded no puede despachar comandos a otro aggregate, y no existe
Process Manager en este proyecto (se evaluó deliberadamente y se descartó para este caso:
un Process Manager solo reacciona a eventos, y un fallo de validación de
`SetAccountTransaction` no genera evento — con lo que un PM nunca se enteraría del fallo
y el diseño de "nunca perder un movimiento" quedaría en riesgo).

En su lugar, `Conta.Reconciliation.confirm_movement/1` (función síncrona de contexto)
hace, para cada movimiento a confirmar:

0. Si el movimiento ya está marcado como `transacted: true` (ver evento
   `MovementTransacted` más abajo — significa que un intento anterior ya creó la
   transacción pero falló al retirarlo del agregado), **se salta directamente al paso
   2**: no se vuelve a construir ni despachar `SetAccountTransaction`, solo se
   reintenta `RemoveMovement`. Esto evita crear una transacción duplicada si el usuario
   pulsa "Confirmar" de nuevo sobre esa fila.
1. Construye el changeset de `SetAccountTransaction` a partir del movimiento:
   `ledger = "default"` (igual que el resto de la app; no hay selección de ledger por
   registro en ningún otro flujo existente) y `on_date = movement.on_date`; dos
   entries, una para `asset_account_name` (que debe ser de tipo `assets`) y otra para
   `account_name` (la contrapartida), **ambas con `description = movement.description`**
   (mismo valor duplicado en las dos entries, igual que hace `enable_breakdown/1` en
   `entry_live/form_component/account_transaction.ex:95-113` al repartir una única
   descripción entre ambas entries). El movimiento temporal **no** tiene un campo
   `ledger` propio.
   `SetAccountTransaction.Entry` tiene `debit`/`credit` independientes (no un importe con
   signo), así que la conversión desde el `amount` con signo del movimiento sigue esta
   convención fija:
   - `amount > 0` (entrada de dinero): entry de `asset_account_name` con `debit =
     amount`; entry de `account_name` con `credit = amount`.
   - `amount < 0` (salida de dinero): entry de `asset_account_name` con `credit =
     abs(amount)`; entry de `account_name` con `debit = abs(amount)`.
   - `amount == 0`: se rechaza antes de construir el changeset (no genera transacción;
     el movimiento se trata como error de validación igual que un `{:error, reason}` del
     punto 3, con el mensaje "importe cero no puede confirmarse").

   Se asume que tanto `asset_account_name` como `account_name` están en la misma
   `currency` que el movimiento (no se usan `change_currency`/`change_debit`/
   `change_credit` en esta versión); si alguna de las dos no coincide,
   `SetAccountTransaction` lo rechazará como cualquier otra transacción no balanceada
   y el movimiento quedará pendiente con ese error (ver punto 3).
2. Si el resultado del paso 1 es `:ok`, despacha primero `MarkMovementTransacted`
   (marca `transacted: true` en el movimiento) y a continuación `RemoveMovement` para
   retirarlo del listado de pendientes. Si `RemoveMovement` fallara (caso extremo:
   condición de carrera, fallo de infraestructura), el movimiento queda visible de
   nuevo pero ya con `transacted: true` — la pantalla de revisión lo marca visualmente
   como "transacción creada, pendiente de limpieza" (sin checkbox de "Confirmar"
   normal) y un reintento solo repite este mismo paso 2 (gracias al paso 0), nunca
   vuelve a crear la transacción.
3. Si el resultado del paso 1 es `{:error, reason}`, no se despacha nada más — el
   movimiento permanece pendiente sin cambios, y el error se devuelve para mostrarse en
   la fila correspondiente.

**Confirmación en bloque**: cada movimiento seleccionado se procesa de forma
independiente siguiendo el mismo algoritmo (pasos 0-3); un fallo en uno no bloquea ni
revierte los demás. El resultado agregado indica, por movimiento, si se confirmó o
quedó pendiente (y por qué).

### Modelo de datos: movimiento temporal

Campos (aggregate + read-model `reconciliation_movements`):

- `id` (uuid)
- `on_date` (date)
- `description` (string)
- `amount` (money con signo: positivo = entrada, negativo = salida)
- `currency`
- `asset_account_name` (fijado al importar; cuenta assets elegida en la pantalla de subida)
- `account_name` (cuenta contrapartida propuesta por el match, o `nil`; siempre editable)
- `source` (nombre del importador usado; informativo — lo añade el flujo de subida de
  Ledger al despachar `ImportMovements`, **no** forma parte del contrato de salida del
  script Lua del importador)
- `transacted` (boolean, `false` por defecto; interno, no editable por el usuario — ver
  "Confirmación")

### Modelo de datos: regla de concordancia (match)

Campos (aggregate + read-model `reconciliation_match_rules`):

- `id`, `name` (descriptivo)
- `conditions`: lista de tripletas `{field, comparator, value}`
  - `field` ∈ `description | amount | on_date`
  - comparadores mínimos viables por campo:
    - `description`: `contains | equals | regex`
    - `amount`: `equals | greater_than | less_than` — operan sobre el `amount` **con
      signo** del movimiento (positivo = entrada, negativo = salida); p.ej. "mayor que
      -100" incluye salidas de hasta 100 y cualquier entrada, lo cual puede no ser
      intuitivo si el usuario piensa en "importes más grandes" en valor absoluto — se
      documentará así en la UI del formulario de reglas.
    - `on_date`: `equals | between` — `value` se serializa como lista `[from, to]`
      (JSON no soporta tuplas; no se usa `{from, to}` como tupla de Elixir en el dato
      persistido)
- `match_type`: `all | any` — deben cumplirse todas las condiciones, o basta una
- `account_name`: cuenta del ledger a anotar si la regla hace match
- Orden de la lista = prioridad de evaluación; gana la **primera** regla que cumpla
  completamente sus condiciones. Reglas globales (no restringidas a cuenta assets).
- Editar, reordenar o eliminar una regla **solo afecta a importaciones futuras**; los
  movimientos ya pendientes conservan la cuenta (o ausencia de cuenta) que se les
  asignó en su momento y no se re-evalúan retroactivamente (fuera de alcance en esta
  versión).

### Contrato del importador (Lua)

Un importador es una tercera variante de entidad Automation (junto a Shortcut y
Filter), reutilizando el mismo motor Lua/`:table` param. Tiene un único parámetro fijo
`movements` (type `table`): lista de filas ya parseadas del CSV (lista de mapas
columna→valor, cabecera de fichero como claves).

El script Lua devuelve:

```json
{"status": "ok", "commands": [
  {"type": "movement", "data": {"on_date": "...", "description": "...", "amount": ..., "currency": "..."}}
]}
```

Se añade un nuevo `case` `"movement"` en el dispatcher de `Conta.Automator.process_result/2`
(o equivalente en el nuevo contexto) que acumula los datos y despacha `ImportMovements`
una vez procesados todos.

El editor/test-run del importador reutiliza tal cual el mecanismo ya existente para
parámetros `:table` en Shortcuts (pegar JSON de ejemplo en un textarea) — no se
construye infraestructura de parseo de fichero real dentro del editor de pruebas; el
parseo CSV→tabla real solo ocurre en la pantalla de subida de Ledger.

## Pantallas y menú

- **Automation → Importadores** (`/automation/importers`): listado + formulario,
  calcado de `shortcut_live/{index,form}` — nombre, descripción, código Lua, parámetro
  fijo `movements`, botón "Probar" reutilizando el test-run existente.
- **Ledger → Conciliación** (`/ledger/reconciliation/upload`): input de fichero (.csv),
  desplegable de importador, desplegable de cuenta assets **(el desplegable solo lista
  cuentas de tipo `assets`, para garantizar que `asset_account_name` siempre es válida
  en la confirmación)**, botón "Subir e importar" → parsea CSV → invoca el importador
  Lua → despacha `ImportMovements` → redirige a la pantalla de revisión.
- **Ledger → Concordancias** (`/ledger/reconciliation/matches`): listado de reglas
  (reordenable), formulario para añadir condiciones (tripletas), selector `all`/`any`,
  cuenta destino.
- **Ledger → Revisión** (`/ledger/reconciliation`): dos bloques —
  - Bloque superior: movimientos con cuenta ya asignada (automática o manual) —
    **estos son los únicos con checkbox de selección**, ya que son los únicos
    confirmables.
  - Bloque inferior: movimientos sin cuenta — sin checkbox de confirmación (solo
    selector de cuenta y opción de eliminar); no hay nada que "saltarse" porque no
    pueden confirmarse hasta tener cuenta.
  - Al asignar cuenta a un movimiento del bloque inferior, sube al bloque superior
    (ahora con su checkbox disponible).
  - Botón único **"Confirmar"** (visible junto al bloque superior): confirma los
    movimientos seleccionados de ese bloque (procesados de forma independiente, con
    feedback de éxito/error por fila).
  - Edición inline (cuenta, importe, descripción, fecha) y eliminar fila, en ambos
    bloques — **excepto** en filas `transacted: true` (ver siguiente punto).
  - Fila con `transacted: true` (transacción ya creada, pendiente de retirar del
    agregado — caso raro de fallo en `RemoveMovement`): aparece en el bloque superior,
    **sin checkbox** de "Confirmar" (no debe volver a intentarse `SetAccountTransaction`)
    y **sin edición inline** (la transacción ya se creó con los datos originales,
    editarla ahora no cambiaría nada real). Se muestra con un aviso visual distinto
    ("transacción creada, pendiente de limpieza") y su botón **"Eliminar" se repropone
    como la única acción disponible**: reintenta solo `RemoveMovement` (el mismo paso 2
    de `confirm_movement/1`), nunca vuelve a crear la transacción.

## Fases de implementación (TDD)

1. **Aggregate `Reconciliation` (núcleo)** — comandos/eventos de reglas de match
   (`SetMatchRule`/`RemoveMatchRule`/`ReorderMatchRules`) y movimientos
   (`ImportMovements`/`UpdateMovement`/`RemoveMovement`/`MarkMovementTransacted`),
   evaluación de reglas al importar y al editar (cuando `account_name` es `nil`),
   projectors de `reconciliation_match_rules` y `reconciliation_movements`. Todo a nivel
   aggregate/projector, sin UI.
2. **Orquestación de confirmación** — `Conta.Reconciliation.confirm_movement/1`
   implementando el algoritmo de 4 pasos (0: si `transacted: true`, saltar a retirar;
   1: dispatch `SetAccountTransaction`; 2: si `:ok`, `MarkMovementTransacted` +
   `RemoveMovement`; 3: si error, se queda pendiente), con soporte para confirmar en
   lote de forma independiente por fila.
3. **Importadores** (Automation) — nuevo tipo de entidad Lua (`movements` como único
   param table), CRUD + test-run reutilizando la infra de Shortcuts, nuevo caso
   `"movement"` en el dispatcher de comandos Lua.
4. **Pantalla de subida** (Ledger → Conciliación) — parseo CSV (NimbleCSV), selección
   de importador + cuenta assets, invocación del importador y `ImportMovements`.
5. **Pantalla de Concordancias** — CRUD de reglas + reordenar.
6. **Pantalla de Revisión** — layout de dos bloques, edición inline, confirmar/eliminar,
   confirmación en bloque con feedback por fila.

Cada fase se implementa con TDD (test primero) antes de pasar a la siguiente.
