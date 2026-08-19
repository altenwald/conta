# Plan de Implementación: Soporte para Ficheros Excel .xls

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Añadir soporte completo para archivos con extensión `.xls` (cubriendo HTML table export, XML SpreadsheetML 2003 y binario BIFF8/OLE2) en la importación de extractos bancarios de conciliación.

**Architecture:**
1. Extender `Conta.Reconciliation.ExcelImport` para detectar el formato subyacente (XLSX, HTML table, SpreadsheetML XML, BIFF8 OLE2) y procesar las celdas en la matriz común de filas.
2. Actualizar `ContaWeb.ReconciliationLive.Upload` para aceptar `.xls` (`accept: ~w(.csv .xlsx .xls)`).
3. Actualizar textos de ayuda en `upload.html.heex`.

**Tech Stack:** Elixir, Phoenix LiveView, Erlang OTP (`:zip`), ExUnit.

**Spec:** `docs/superpowers/specs/2026-08-19-xls-support-design.md`

---

### Task 1: Tests unitarios para soporte de .xls en `ExcelImportTest`

**Archivos:**
- Modificar: `apps/conta/test/conta/reconciliation/excel_import_test.exs`

- [x] **Paso 1: Escribir tests unitarios en `excel_import_test.exs` para:**
  - Archivo `.xls` con formato HTML table bancario con metadatos y tabla de movimientos.
  - Archivo `.xls` con formato XML SpreadsheetML 2003.
  - Archivo `.xls` con formato binario BIFF8 / OLE2.
- [x] **Paso 2: Ejecutar tests y verificar que fallan**

---

### Task 2: Implementar decodificadores de .xls en `Conta.Reconciliation.ExcelImport`

**Archivos:**
- Modificar: `apps/conta/lib/conta/reconciliation/excel_import.ex`

- [x] **Paso 1: Implementar detección de formato por contenido en `ExcelImport.parse/1`**
- [x] **Paso 2: Implementar parser de HTML table (`parse_html_table/1`)**
- [x] **Paso 3: Implementar parser de SpreadsheetML 2003 (`parse_spreadsheet_xml/1`)**
- [x] **Paso 4: Implementar parser de BIFF8 / OLE2 (`parse_biff8_ole2/1`)**
- [x] **Paso 5: Ejecutar tests unitarios y verificar que pasan**

---

### Task 3: Integración en `ContaWeb.ReconciliationLive.Upload`

**Archivos:**
- Modificar: `apps/conta_web/lib/conta_web/live/reconciliation_live/upload.ex`
- Modificar: `apps/conta_web/lib/conta_web/live/reconciliation_live/upload.html.heex`
- Modificar: `apps/conta_web/test/conta_web/live/reconciliation_live/upload_test.exs`

- [x] **Paso 1: Escribir test en `upload_test.exs` para subida de archivo con extensión `.xls`**
- [x] **Paso 2: Ejecutar test y verificar fallo**
- [x] **Paso 3: Actualizar `upload.ex` (`accept: ~w(.csv .xlsx .xls)` y `parse_statement/2`) y `upload.html.heex`**
- [x] **Paso 4: Ejecutar test y verificar que pasa**

---

### Task 4: Verificación completa del proyecto

- [x] **Paso 1: Ejecutar `mix test` en el proyecto paraguas**
- [x] **Paso 2: Ejecutar `mix format` y verificar estado general**
