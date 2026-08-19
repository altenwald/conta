# Plan de Implementación: Transformaciones en Reglas de Match y Soporte Excel (.xlsx)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permitir transformar la descripción/concepto en las reglas de correspondencia de conciliación (mediante texto fijo o grupos capturados por expresiones regulares) y soportar la importación directa de extractos bancarios en formato Excel (.xlsx) con detección automática de cabeceras.

**Architecture:** 
1. Añadir el campo opcional `concept` al comando `SetMatchRule`, evento `MatchRuleSet`, tabla de base de datos y proyector `MatchRule`.
2. Actualizar el agregado `Conta.Aggregate.Reconciliation` para aplicar la transformación del concepto durante la importación de movimientos (`ImportMovements`), soportando sustitución mediante `Regex.replace/3` o reemplazo de texto.
3. Crear el parser `Conta.Reconciliation.ExcelImport` en `apps/conta` utilizando `:zip` y parseo XML para hojas y cadenas compartidas de `.xlsx`, con detección automática de la primera fila de cabecera válida.
4. Actualizar `ContaWeb.ReconciliationLive.Upload` para aceptar `.xlsx` y parsear el extracto bancario según la extensión.
5. Añadir el campo `concept` en el formulario y listado de reglas de match en `ContaWeb.ReconciliationLive.Matches`.

**Tech Stack:** Elixir, Phoenix LiveView, Commanded CQRS/ES, Ecto / PostgreSQL, Erlang OTP (`:zip`, `:xmerl`), ExUnit, `Phoenix.LiveViewTest`.

**Spec:** `docs/superpowers/specs/2026-08-19-reconciliation-transformations-and-excel-design.md`

---

### Task 1: Migración Ecto para añadir `concept` a `reconciliation_match_rules`

**Archivos:**
- Crear: `apps/conta/priv/repo/migrations/YYYYMMDDHHMMSS_add_concept_to_reconciliation_match_rules.exs`

- [x] **Paso 1: Generar archivo de migración con `mix ecto.gen.migration`**
- [x] **Paso 2: Escribir la migración añadiendo `add :concept, :string`**
- [x] **Paso 3: Ejecutar migración en dev y test (`mix ecto.migrate && MIX_ENV=test mix ecto.migrate`)**

---

### Task 2: Actualizar `SetMatchRule`, `MatchRuleSet` y `Projector.Reconciliation.MatchRule`

**Archivos:**
- Modificar: `apps/conta/lib/conta/command/set_match_rule.ex`
- Modificar: `apps/conta/lib/conta/event/match_rule_set.ex`
- Modificar: `apps/conta/lib/conta/projector/reconciliation/match_rule.ex`
- Modificar: `apps/conta/lib/conta/reconciliation.ex` (`get_set_match_rule/1`)
- Modificar: `apps/conta/test/projector/reconciliation_test.exs`

- [x] **Paso 1: Escribir test fallido para proyector con `concept`**
- [x] **Paso 2: Ejecutar test y verificar que falla**
- [x] **Paso 3: Añadir campo `:concept` al comando, evento, proyector y helper `get_set_match_rule`**
- [x] **Paso 4: Ejecutar test y verificar que pasa**

---

### Task 3: Lógica de Transformación de Concepto en el Agregado `Reconciliation`

**Archivos:**
- Modificar: `apps/conta/lib/conta/aggregate/reconciliation.ex`
- Modificar: `apps/conta/test/aggregate/reconciliation_test.exs`

- [x] **Paso 1: Escribir tests unitarios en `reconciliation_test.exs` para:**
  - Regla de match con concepto estático que reemplaza la descripción del movimiento.
  - Regla de match con condición regex (`field: :description, comparator: :regex`) y concepto con captura (ej. `"Factura \\1"` o `"Ref: $1"`).
  - Regla de match sin concepto que preserva la descripción original intacta.
- [x] **Paso 2: Ejecutar tests y verificar que fallan**
- [x] **Paso 3: Implementar `transform_description/2` y actualizar `evaluate_rules/2` en `Conta.Aggregate.Reconciliation`**
- [x] **Paso 4: Ejecutar tests y verificar que pasan**

---

### Task 4: Parser de Excel `Conta.Reconciliation.ExcelImport`

**Archivos:**
- Crear: `apps/conta/lib/conta/reconciliation/excel_import.ex`
- Crear: `apps/conta/test/conta/reconciliation/excel_import_test.exs`

- [x] **Paso 1: Escribir tests unitarios para `ExcelImport.parse/1`:**
  - Archivo vacío o binario corrupto -> `{:error, :empty_file}` / `{:error, :invalid_excel}`.
  - Hoja `.xlsx` normal -> extrae lista de mapas con claves de cabecera.
  - Hoja `.xlsx` con metadatos iniciales (filas de título/saldo antes de la cabecera real) -> detecta la fila de cabecera correcta e ignora las iniciales.
- [x] **Paso 2: Ejecutar tests y verificar que fallan**
- [x] **Paso 3: Implementar `Conta.Reconciliation.ExcelImport`:**
  - Descompresión de archivo `.xlsx` en memoria con `:zip`.
  - Extracción y mapeo de `xl/sharedStrings.xml` e inline strings.
  - Parseo de celdas de `xl/worksheets/sheet1.xml`.
  - Detección de fila de cabecera y construcción de mapas.
- [x] **Paso 4: Ejecutar tests y verificar que pasan**

---

### Task 5: Actualizar interfaz Web para reglas de Match (`Form` y `Index`)

**Archivos:**
- Modificar: `apps/conta_web/lib/conta_web/live/reconciliation_live/matches/form.html.heex`
- Modificar: `apps/conta_web/lib/conta_web/live/reconciliation_live/matches/index.html.heex`
- Modificar: `apps/conta_web/test/conta_web/live/reconciliation_live/matches/form_test.exs` (si existe) o `apps/conta_web/test/conta_web/live/reconciliation_live/`

- [x] **Paso 1: Escribir/actualizar tests LiveView para guardar regla con campo `concept`**
- [x] **Paso 2: Ejecutar tests y verificar fallo**
- [x] **Paso 3: Añadir input de `concept` en el formulario y columna en la tabla de listado**
- [x] **Paso 4: Ejecutar tests y verificar que pasan**

---

### Task 6: Soporte para subida de `.xlsx` en `ReconciliationLive.Upload`

**Archivos:**
- Modificar: `apps/conta_web/lib/conta_web/live/reconciliation_live/upload.ex`
- Modificar: `apps/conta_web/lib/conta_web/csv_import_messages.ex` (ampliar a mensajes de importación de extractos)
- Modificar: `apps/conta_web/test/conta_web/live/reconciliation_live/upload_test.exs`

- [x] **Paso 1: Escribir tests en `upload_test.exs` para subida y procesamiento de un `.xlsx`**
- [x] **Paso 2: Ejecutar tests y verificar que fallan**
- [x] **Paso 3: Implementar soporte de `.xlsx` en `upload.ex` detectando la extensión/tipo y usando `ExcelImport`**
- [x] **Paso 4: Ejecutar tests y verificar que pasan**

---

### Task 7: Verificación Final del Proyecto

- [x] **Paso 1: Ejecutar toda la suite de pruebas `mix test`**
- [x] **Paso 2: Ejecutar `mix check` y verificar que el código cumple con todas las directrices**
