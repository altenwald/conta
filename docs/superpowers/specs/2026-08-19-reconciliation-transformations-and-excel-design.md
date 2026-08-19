# Especificación de Diseño: Transformaciones en Reglas de Conciliación y Soporte de Ficheros Excel (.xlsx)

**Fecha:** 2026-08-19  
**Autor:** Antigravity  
**Estado:** Borrador de Diseño

---

## 1. Contexto y Motivación

El sistema de conciliación bancaria (`Conta.Reconciliation`) permite importar extractos bancarios, evaluar reglas de correspondencia (`MatchRule`) para asignar automáticamente las cuentas de contrapartida (`account_name`) y revisar/confirmar los movimientos antes de asentar las transacciones contables en el libro mayor (`Ledger`).

Actualmente existen dos limitaciones críticas para el uso real con entidades bancarias:
1. **Falta de transformación del concepto**: Cuando una regla hace match, solo asigna la cuenta contable (`account_name`). La descripción original del banco (que a menudo contiene códigos sucios, sufijos de tarjeta, etc.) se mantiene intacta. Se necesita permitir transformar la descripción/concepto resultante (ej. reemplazar por un texto limpio "Combustible" o sustituir grupos de una expresión regular como `Factura \1`).
2. **Soporte exclusivo para CSV**: La mayoría de bancos españoles e internacionales exportan sus extractos en formato Excel (`.xlsx`) en lugar de CSV, y frecuentemente insertan filas de metadatos (IBAN, titular, saldo inicial) antes de la cabecera real de movimientos.

---

## 2. Alcance

1. **Transformaciones en `MatchRule`**:
   - Añadir campo opcional `concept` a las reglas de match.
   - En la evaluación de reglas (`Conta.Aggregate.Reconciliation`), si la regla coincide y define `concept`:
     - Si la condición de la regla contiene una expresión regular sobre la descripción (`comparator: :regex`), aplicar sustitución de grupos mediante `Regex.replace/3` sobre el concepto especificado (soportando referencias `\1`, `\2`, `$1`, etc.).
     - En caso de comparadores simples (`contains`, `equals`), sustituir la descripción directamente por el texto de `concept`.
   - Persistir `concept` en el agregado, eventos (`MatchRuleSet`) y proyector (`reconciliation_match_rules`).
   - Actualizar el formulario y listado de reglas en `ContaWeb.ReconciliationLive.Matches`.

2. **Parser de Excel (`.xlsx`)**:
   - Crear el módulo `Conta.Reconciliation.ExcelImport` en `apps/conta/lib/conta/reconciliation/excel_import.ex`.
   - Soporte para descompresión de archivos `.xlsx` (`:zip`) y parseo de celdas (`xl/worksheets/sheet1.xml` y `xl/sharedStrings.xml`).
   - Algoritmo de detección automática de cabeceras: omitir filas previas de metadatos/resumen hasta encontrar la fila de cabecera válida con columnas bancarias.
   - Mapear cada fila subsiguiente a un mapa `%{ "Cabecera" => "Valor" }`, produciendo la misma estructura de datos que consume `Conta.Automator.run_importer/4`.

3. **Integración en la interfaz de subida (`Upload`)**:
   - Permitir la subida de `.xlsx` en `ContaWeb.ReconciliationLive.Upload` (`accept: ~w(.csv .xlsx)`).
   - Unificar la gestión de errores en `ContaWeb.StatementImportMessages`.

---

## 3. Decisiones Técnicas y Arquitectura

### 3.1. Dominio y Event Sourcing (`apps/conta`)

#### A. Esquema y Eventos de `MatchRule`
- `Conta.Command.SetMatchRule`: añade campo opcional `:concept, :string`.
- `Conta.Event.MatchRuleSet`: añade campo opcional `:concept, :string`.
- `Conta.Projector.Reconciliation.MatchRule`: añade campo `:concept, :string`.
- Migración Ecto: `add :concept, :string` en la tabla `reconciliation_match_rules`.

#### B. Evaluación de Reglas en el Agregado (`Conta.Aggregate.Reconciliation`)
```elixir
defp evaluate_rules(match_rules, movement) do
  Enum.find_value(match_rules, fn rule ->
    if rule_matches?(rule, movement) do
      new_description = transform_description(rule, movement.description)
      {rule.account_name, new_description}
    end
  end)
end
```
Cuando `ImportMovements` se ejecuta:
- Si una regla coincide:
  - `account_name = rule.account_name`
  - `description = transformed_description || movement.description`

#### C. Lógica de Transformación de Expresiones Regulares
Si `rule.concept` está presente:
- Busca si alguna condición de la regla utiliza `comparator: :regex` sobre `field: :description`.
- Si existe una condición regex válida con patrón compilado `regex`:
  - Transforma usando `Regex.replace(regex, original_description, rule.concept)`.
- Si no hay condición regex (o es comparador `contains`/`equals`):
  - Retorna `rule.concept` directamente.

---

### 3.2. Parser de Extractos Excel (`Conta.Reconciliation.ExcelImport`)

El formato `.xlsx` es un contenedor zip (Open Packaging Conventions) con ficheros XML:
- `xl/sharedStrings.xml`: Tabla de cadenas únicas para celdas de tipo string (`<c t="s"><v>0</v></c>`).
- `xl/worksheets/sheet1.xml`: Matriz de filas `<row r="N">` y celdas `<c r="A1" ...><v>...</v></c>`.
- `xl/workbook.xml`: Metadatos del libro y hojas.

#### Detección de Cabecera y Filas
1. Extraer las cadenas de `xl/sharedStrings.xml`.
2. Leer las filas de la primera hoja (`sheet1.xml`).
3. Para cada fila, mapear las celdas a sus valores correspondientes según el tipo (`s` = shared string, `inlineStr` = inline string, `n`/defecto = número/texto).
4. **Detección de Cabecera**:
   - Recorrer filas desde el inicio. La primera fila que contenga al menos 2 celdas de texto no vacías se considera la cabecera.
   - Si no se encuentra una cabecera con al menos 2 columnas, retornar `{:error, :no_headers_found}`.
5. **Extracción de Datos**:
   - Todas las filas posteriores con datos se mapean a mapas con claves basadas en los nombres de columna de la cabecera detectada.
   - Se ignoran filas completamente vacías al final del archivo.

---

### 3.3. Adaptador Web (`apps/conta_web`)

1. **`ContaWeb.ReconciliationLive.Upload`**:
   - `allow_upload(:statement, accept: ~w(.csv .xlsx), max_entries: 1)`
   - Detecta la extensión o el tipo de archivo y despacha a `CsvImport.parse/1` o `ExcelImport.parse/1`.
2. **`ContaWeb.ReconciliationLive.Matches.Form`**:
   - Añade el campo `<.input field={@form[:concept]} type="text" label="Concepto transformado (opcional)" />` con texto explicativo para reemplazos estáticos y regex (`\1`, `$1`).
3. **`ContaWeb.ReconciliationLive.Matches.Index`**:
   - Añade columna en la tabla de reglas para visualizar el concepto transformado si está configurado.

---

## 4. Pruebas y Validación (TDD)

- **Unit Tests Agregado**: Pruebas de `SetMatchRule` con `concept`, y evaluación de `ImportMovements` con transformaciones estáticas y con expresiones regulares capturadas.
- **Unit Tests ExcelImport**: Pruebas de parseo de archivos `.xlsx` generados dinámicamente con `Conta.Automator.Excel` y casos con filas de metadatos iniciales.
- **Integration Tests LiveView**:
  - Creación/edición de reglas de match con campo `concept`.
  - Subida de fichero `.xlsx` en `ReconciliationLive.Upload` y verificación de movimientos en `ReconciliationLive.Review`.
