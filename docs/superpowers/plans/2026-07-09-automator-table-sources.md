# Fuentes de datos reales para parámetros `table` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cuando un parámetro de un Filter/Shortcut es de tipo `table`, el campo `name` deja de ser texto libre y se restringe a un registro de fuentes de datos reales (`expenses`, `invoices`); el panel "Test data" gana un botón para rellenar el JSON con una muestra real (tamaño configurable por parámetro), y los controllers de producción dejan de depender de un string literal para inyectar los datos reales.

**Architecture:** Nuevo módulo `Conta.Automator.TableSources` (registro nombre → función de muestreo). Nuevo campo `sample_limit` en los 5 embedded schemas `Param` del pipeline comando → evento → proyector (sin migración, `params` es `jsonb`). Dos sitios de conversión manual (`get_set_filter/1`, `get_set_shortcut/1`) actualizados para no perder el campo al recargar el formulario de edición. UI: `ContaWeb.AutomatorComponents.test_param_input/1` gana un botón "Load real data"; los formularios de Filter/Shortcut restringen el `<select>` de `name` y añaden un input de tamaño de muestra cuando el tipo es `table`.

**Tech Stack:** Elixir/Phoenix/Ecto/Commanded (event sourcing), Phoenix LiveView, ExUnit, ExMachina.

**Desviación respecto a la spec** (`docs/superpowers/specs/2026-07-09-automator-table-sources-design.md`): la spec listaba 4 sitios de "conversión manual", incluyendo `to_projector_params/1` en `automator.ex`. Durante la planificación se confirmó que ese sitio construye un `Projector.Param` **efímero**, usado solo por `Automator.cast/2` y `validate_params/2` — ninguno de los dos lee `.sample_limit`. Propagar el campo ahí no tendría ningún efecto observable, así que se omite (YAGNI). Los otros 3 sitios (dos schemas de comando/evento + el allowlist de `Jason.Encoder`) sí son necesarios y están en el plan.

---

### Task 1: `Book.list_invoices_filtered/2` acepta un límite

**Files:**
- Modify: `apps/conta/lib/conta/book.ex:71-77`
- Test: `apps/conta/test/conta/book_test.exs`

- [ ] **Step 1: Write the failing test**

Añadir dentro del `describe "invoices"` existente, después del test `"list_invoices_filtered/1 with status unpaid"` (línea ~54):

```elixir
    test "list_invoices_filtered/2 respects the limit" do
      insert(:invoice, %{invoice_number: "2023-00001"})
      insert(:invoice, %{invoice_number: "2023-00002"})
      insert(:invoice, %{invoice_number: "2023-00003"})

      assert length(Book.list_invoices_filtered([], 2)) == 2
      assert length(Book.list_invoices_filtered([])) == 3
    end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test apps/conta/test/conta/book_test.exs -k "respects the limit"`
Expected: FAIL — `Book.list_invoices_filtered/2` no existe (`UndefinedFunctionError` o `BadArityError` porque hoy solo hay `/1`).

- [ ] **Step 3: Write minimal implementation**

En `apps/conta/lib/conta/book.ex:71-77`, sustituir:

```elixir
  def list_invoices_filtered(filters) do
    from(i in Invoice, order_by: [desc: :invoice_number])
    |> filter(filters[:term], &by_term/2)
    |> filter(filters[:year], &by_year/2)
    |> filter(filters[:status], &by_status/2)
    |> Repo.all()
  end
```

por:

```elixir
  def list_invoices_filtered(filters, limit \\ :infinity) do
    from(i in Invoice, order_by: [desc: :invoice_number])
    |> filter(filters[:term], &by_term/2)
    |> filter(filters[:year], &by_year/2)
    |> filter(filters[:status], &by_status/2)
    |> apply_limit(limit)
    |> Repo.all()
  end

  defp apply_limit(query, :infinity), do: query
  defp apply_limit(query, limit) when is_integer(limit), do: from(q in query, limit: ^limit)
```

(Coloca `apply_limit/2` justo después de las funciones `filter/3` privadas existentes, línea ~81.)

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test apps/conta/test/conta/book_test.exs`
Expected: PASS (todos los tests de `describe "invoices"`, incluido el nuevo).

- [ ] **Step 5: Commit**

```bash
git add apps/conta/lib/conta/book.ex apps/conta/test/conta/book_test.exs
git commit -m "Add optional limit to Book.list_invoices_filtered/2"
```

---

### Task 2: `Conta.Automator.TableSources`

**Files:**
- Create: `apps/conta/lib/conta/automator/table_sources.ex`
- Test: `apps/conta/test/conta/automator/table_sources_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule Conta.Automator.TableSourcesTest do
  use Conta.DataCase
  import Conta.BookFixtures

  alias Conta.Automator.TableSources
  alias Conta.Projector.Book.Expense

  describe "names/0 and options/0" do
    test "expose the two known sources" do
      assert TableSources.names() == ["expenses", "invoices"]
      assert TableSources.options() == [{"Expenses", "expenses"}, {"Invoices", "invoices"}]
    end
  end

  describe "known?/1" do
    test "true for a registered source" do
      assert TableSources.known?("expenses")
    end

    test "false for anything else" do
      refute TableSources.known?("gastos")
    end
  end

  describe "expenses_key/0, invoices_key/0, default_sample_limit/0" do
    test "expose the canonical keys and default" do
      assert TableSources.expenses_key() == "expenses"
      assert TableSources.invoices_key() == "invoices"
      assert TableSources.default_sample_limit() == 5
    end
  end

  describe "sample/2" do
    test "returns up to `limit` real invoices for the invoices source" do
      insert(:invoice, %{invoice_number: "2023-00001"})
      insert(:invoice, %{invoice_number: "2023-00002"})

      assert length(TableSources.sample("invoices", 1)) == 1
    end

    test "returns up to `limit` real expenses for the expenses source" do
      Repo.insert!(%Expense{
        name: "Office supplies",
        invoice_number: "EXP-001",
        invoice_date: ~D[2024-01-15],
        currency: :EUR
      })

      Repo.insert!(%Expense{
        name: "Travel",
        invoice_number: "EXP-002",
        invoice_date: ~D[2024-02-15],
        currency: :EUR
      })

      assert length(TableSources.sample("expenses", 1)) == 1
    end

    test "returns an error tuple for an unknown source" do
      assert TableSources.sample("gastos", 5) == {:error, :unknown_source}
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test apps/conta/test/conta/automator/table_sources_test.exs`
Expected: FAIL — `Conta.Automator.TableSources` no existe (`UndefinedFunctionError`).

- [ ] **Step 3: Write minimal implementation**

```elixir
defmodule Conta.Automator.TableSources do
  @moduledoc """
  Registro de fuentes de datos reales disponibles para un parámetro
  `:table` de un Filter/Shortcut — usado por el botón "Load real data"
  del panel de pruebas y por los controllers de exportación
  (`ContaWeb.ExpenseController`, `ContaWeb.InvoiceController`).
  """

  alias Conta.Book

  @expenses_key "expenses"
  @invoices_key "invoices"
  @default_sample_limit 5

  @sources %{
    @expenses_key => %{
      label: "Expenses",
      sample: fn limit -> Book.list_simple_expenses_filtered([], limit) end
    },
    @invoices_key => %{
      label: "Invoices",
      sample: fn limit -> Book.list_invoices_filtered([], limit) end
    }
  }

  @spec expenses_key() :: String.t()
  def expenses_key, do: @expenses_key

  @spec invoices_key() :: String.t()
  def invoices_key, do: @invoices_key

  @spec default_sample_limit() :: pos_integer()
  def default_sample_limit, do: @default_sample_limit

  @spec names() :: [String.t()]
  def names, do: Map.keys(@sources)

  @spec options() :: [{String.t(), String.t()}]
  def options, do: Enum.map(@sources, fn {name, %{label: label}} -> {label, name} end)

  @spec known?(String.t()) :: boolean()
  def known?(name), do: Map.has_key?(@sources, name)

  @spec sample(String.t(), pos_integer()) :: [struct()] | {:error, :unknown_source}
  def sample(name, limit) do
    case @sources[name] do
      %{sample: fun} -> fun.(limit)
      nil -> {:error, :unknown_source}
    end
  end
end
```

Nota: `Enum.map/2` sobre `@sources` (un `Map`) no garantiza orden de iteración en general, pero con solo 2 claves fijas y Erlang/OTP moderno, el orden de un mapa literal pequeño con claves de igual tipo es estable entre llamadas dentro del mismo run de la VM. Si el test de `names/0`/`options/0` falla por orden, ajústalo a `assert Enum.sort(TableSources.names()) == ["expenses", "invoices"]` en vez de comparar la lista exacta — no cambia nada del código de producción.

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test apps/conta/test/conta/automator/table_sources_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add apps/conta/lib/conta/automator/table_sources.ex apps/conta/test/conta/automator/table_sources_test.exs
git commit -m "Add Conta.Automator.TableSources registry for real table-param samples"
```

---

### Task 3: Campo `sample_limit` en los 5 schemas `Param`

**Files:**
- Modify: `apps/conta/lib/conta/command/set_filter.ex:14-18,35-36`
- Modify: `apps/conta/lib/conta/command/set_shortcut.ex:12-16,33-34`
- Modify: `apps/conta/lib/conta/event/filter_set.ex:16-20,38-39`
- Modify: `apps/conta/lib/conta/event/shortcut_set.ex:14-18,36-37`
- Modify: `apps/conta/lib/conta/projector/automator/param.ex`
- Test: `apps/conta/test/aggregate/automator_test.exs`
- Test: `apps/conta/test/projector/automator_test.exs`
- Test: `apps/conta/test/conta/automator_context_test.exs`

- [ ] **Step 1: Write the failing tests**

En `apps/conta/test/aggregate/automator_test.exs`, añadir un nuevo `describe` (el fichero no tiene alias de `SetFilter`/`FilterSet` todavía, hay que añadirlos):

```elixir
defmodule Aggregate.AutomatorTest do
  use ExUnit.Case

  alias Conta.Aggregate.Automator
  alias Conta.Command.SetFilter
  alias Conta.Command.SetShortcut
  alias Conta.Event.FilterSet
  alias Conta.Event.ShortcutSet

  describe "shortcut" do
    # ... (test existente sin cambios)
  end

  describe "filter" do
    test "a table param's sample_limit survives command -> event" do
      automator = %Automator{}

      command = %SetFilter{
        automator: "automator",
        name: "my filter",
        output: :json,
        code: "-- lua",
        params: [%SetFilter.Param{name: "expenses", type: :table, sample_limit: 10}]
      }

      assert %FilterSet{params: [%FilterSet.Param{name: "expenses", type: :table, sample_limit: 10}]} =
               Automator.execute(automator, command)
    end
  end
end
```

En `apps/conta/test/projector/automator_test.exs`, añadir un nuevo `describe "filter"` (el fichero solo limpia `Automator.Shortcut`/`ProjectionVersion` en `on_exit`; hay que ampliarlo para no dejar basura entre tests):

```elixir
  setup do
    version =
      if pv = Repo.get(Automator.ProjectionVersion, "Conta.Projector.Automator") do
        pv.last_seen_version + 1
      else
        1
      end

    on_exit(fn ->
      Repo.delete_all(Automator.Shortcut)
      Repo.delete_all(Automator.Filter)
      Repo.delete_all(Automator.ProjectionVersion)
    end)

    %{
      handler_name: "Conta.Projector.Automator",
      event_number: version
    }
  end

  describe "shortcut" do
    # ... (test existente sin cambios)
  end

  describe "filter" do
    test "persists a table param's sample_limit", metadata do
      event = %Conta.Event.FilterSet{
        automator: "automator",
        name: "expenses report",
        output: :json,
        code: "-- lua",
        params: [%Conta.Event.FilterSet.Param{name: "expenses", type: :table, sample_limit: 10}]
      }

      assert :ok = Automator.handle(event, metadata)

      filter = Repo.get_by!(Automator.Filter, name: "expenses report", automator: "automator")
      assert [%Automator.Param{name: "expenses", type: :table, sample_limit: 10}] = filter.params
    end
  end
```

Además, añade este test independiente (no necesita DB) en `apps/conta/test/conta/automator_context_test.exs`, dentro de `describe "validate_params/2 — pure logic, no DB nor ES"` (después del test `"cast table param defaults missing value to an empty table"`). Cubre justo la regresión que preocupaba a la spec (sección 6): que `sample_limit` no se quede fuera del JSON del API por el `@derive {Jason.Encoder, only: [...]}` de `Conta.Projector.Automator.Param`:

```elixir
    test "sample_limit survives Jason encoding of a Param (API detail response allowlist)" do
      param = %Param{name: "expenses", type: :table, sample_limit: 7}

      assert %{"sample_limit" => 7} = Jason.decode!(Jason.encode!(param))
    end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test apps/conta/test/aggregate/automator_test.exs apps/conta/test/projector/automator_test.exs apps/conta/test/conta/automator_context_test.exs`
Expected: FAIL to compile — `sample_limit` no es un campo de `SetFilter.Param`/`FilterSet.Param`/`Automator.Param` (`KeyError` sobre struct desconocido en tiempo de compilación).

- [ ] **Step 3: Write minimal implementation**

En `apps/conta/lib/conta/command/set_filter.ex`, dentro de `embeds_many :params, Param do` (líneas 14-18):

```elixir
    embeds_many :params, Param do
      field :name, :string
      field :type, Ecto.Enum, values: ~w[string date integer money currency options account_name table]a
      field :options, {:array, :string}
      field :sample_limit, :integer
    end
```

Y en `@optional_fields` de `changeset_params/2` (línea 36):

```elixir
  @optional_fields ~w[options sample_limit]a
```

Repite el mismo cambio (campo + `@optional_fields`) en:
- `apps/conta/lib/conta/command/set_shortcut.ex` (líneas 12-16 y 34)
- `apps/conta/lib/conta/event/filter_set.ex` (líneas 16-20 y 39)
- `apps/conta/lib/conta/event/shortcut_set.ex` (líneas 14-18 y 37)

En `apps/conta/lib/conta/projector/automator/param.ex`:

```elixir
defmodule Conta.Projector.Automator.Param do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  @derive {Jason.Encoder, only: ~w[name type options sample_limit]a}
  typed_embedded_schema do
    field :name, :string, primary_key: true
    field :type, Ecto.Enum, values: ~w[string date integer money currency options account_name table]a
    field :options, {:array, :string}
    field :sample_limit, :integer
  end

  @required_fields ~w[name type]a
  @optional_fields ~w[options sample_limit]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test apps/conta/test/aggregate/automator_test.exs apps/conta/test/projector/automator_test.exs apps/conta/test/conta/automator_context_test.exs`
Expected: PASS

- [ ] **Step 5: Run the full existing automator test suite to check for regressions**

Run: `mix test apps/conta/test/conta/automator_context_test.exs apps/conta/test/conta/automator/table_sources_test.exs`
Expected: PASS (sin cambios de comportamiento para los tests ya existentes; `sample_limit` es opcional en todos lados)

- [ ] **Step 6: Commit**

```bash
git add apps/conta/lib/conta/command/set_filter.ex apps/conta/lib/conta/command/set_shortcut.ex \
        apps/conta/lib/conta/event/filter_set.ex apps/conta/lib/conta/event/shortcut_set.ex \
        apps/conta/lib/conta/projector/automator/param.ex \
        apps/conta/test/aggregate/automator_test.exs apps/conta/test/projector/automator_test.exs \
        apps/conta/test/conta/automator_context_test.exs
git commit -m "Add sample_limit field to Param across command/event/projector schemas"
```

---

### Task 4: `get_set_filter/1` y `get_set_shortcut/1` conservan `sample_limit`

**Files:**
- Modify: `apps/conta/lib/conta/automator.ex:77-92,100-116`
- Test: `apps/conta/test/conta/automator_context_test.exs`

- [ ] **Step 1: Write the failing tests**

Añadir dentro de `describe "filters — DB queries"` (después de `"get_set_filter/1 returns nil for unknown id"`, línea ~106):

```elixir
    test "get_set_filter/1 carries sample_limit for a table param", %{filter: filter} do
      filter =
        filter
        |> Ecto.Changeset.change(
          params: [
            %Conta.Projector.Automator.Param{name: "expenses", type: :table, sample_limit: 7}
          ]
        )
        |> Repo.update!()

      set_filter = Automator.get_set_filter(filter.id)

      assert [%Conta.Command.SetFilter.Param{name: "expenses", type: :table, sample_limit: 7}] =
               set_filter.params
    end
```

Añadir dentro de `describe "shortcuts — DB queries"` (después de `"get_set_shortcut/1 returns nil for unknown id"`, línea ~43):

```elixir
    test "get_set_shortcut/1 carries sample_limit for a table param" do
      shortcut =
        insert(:shortcut, %{
          params: [%Param{name: "expenses", type: :table, sample_limit: 7}]
        })

      set_shortcut = Automator.get_set_shortcut(shortcut.id)

      assert [%Conta.Command.SetShortcut.Param{name: "expenses", type: :table, sample_limit: 7}] =
               set_shortcut.params
    end
```

(`Param` ya está aliasado como `Conta.Projector.Automator.Param` al principio del fichero.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test apps/conta/test/conta/automator_context_test.exs -k "carries sample_limit"`
Expected: FAIL — `set_filter.params`/`set_shortcut.params` no incluyen `sample_limit` (viene `nil` porque `get_set_filter/1`/`get_set_shortcut/1` no lo copian).

- [ ] **Step 3: Write minimal implementation**

En `apps/conta/lib/conta/automator.ex:77-92`:

```elixir
  def get_set_shortcut(%Shortcut{} = shortcut) do
    %SetShortcut{
      name: shortcut.name,
      automator: shortcut.automator,
      params:
        for %Param{} = shortcut_param <- shortcut.params do
          %SetShortcut.Param{
            name: shortcut_param.name,
            type: shortcut_param.type,
            options: shortcut_param.options,
            sample_limit: shortcut_param.sample_limit
          }
        end,
      code: shortcut.code,
      language: shortcut.language
    }
  end
```

Y en `apps/conta/lib/conta/automator.ex:100-116`:

```elixir
  def get_set_filter(%Filter{} = filter) do
    %SetFilter{
      name: filter.name,
      automator: filter.automator,
      output: filter.output,
      params:
        for %Param{} = filter_param <- filter.params do
          %SetFilter.Param{
            name: filter_param.name,
            type: filter_param.type,
            options: filter_param.options,
            sample_limit: filter_param.sample_limit
          }
        end,
      code: filter.code,
      language: filter.language
    }
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test apps/conta/test/conta/automator_context_test.exs`
Expected: PASS (todos, incluidos los 2 nuevos)

- [ ] **Step 5: Commit**

```bash
git add apps/conta/lib/conta/automator.ex apps/conta/test/conta/automator_context_test.exs
git commit -m "Carry sample_limit through get_set_filter/1 and get_set_shortcut/1"
```

---

### Task 5: Controllers de producción usan las claves del registro

**Files:**
- Modify: `apps/conta_web/lib/conta_web/controllers/expense_controller.ex:36-37`
- Modify: `apps/conta_web/lib/conta_web/controllers/invoice_controller.ex:78-79`
- Test: `apps/conta_web/test/conta_web/controllers/expense_controller_test.exs` (nuevo)
- Test: `apps/conta_web/test/conta_web/controllers/invoice_controller_test.exs` (nuevo)

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule ContaWeb.ExpenseControllerTest do
  use ContaWeb.ConnCase

  import Conta.AutomatorFixtures

  alias Conta.AccountsFixtures

  setup do
    %{user: AccountsFixtures.insert(:user) |> AccountsFixtures.confirm_user()}
  end

  describe "GET /books/expenses/run/:automator_id" do
    test "runs the filter, injecting real expenses under the registry key", %{conn: conn, user: user} do
      filter =
        insert(:filter, %{
          type: :expense,
          output: :json,
          code: "return #expenses",
          params: [build(:filter_param, %{name: "expenses", type: :table})]
        })

      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/books/expenses/run/#{filter.id}")

      assert response(conn, 200) == "0"
    end
  end
end
```

```elixir
defmodule ContaWeb.InvoiceControllerTest do
  use ContaWeb.ConnCase

  import Conta.AutomatorFixtures

  alias Conta.AccountsFixtures

  setup do
    %{user: AccountsFixtures.insert(:user) |> AccountsFixtures.confirm_user()}
  end

  describe "GET /books/invoices/run/:automator_id" do
    test "runs the filter, injecting real invoices under the registry key", %{conn: conn, user: user} do
      filter =
        insert(:filter, %{
          type: :invoice,
          output: :json,
          code: "return #invoices",
          params: [build(:filter_param, %{name: "invoices", type: :table})]
        })

      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/books/invoices/run/#{filter.id}")

      assert response(conn, 200) == "0"
    end
  end
end
```

Estos dos tests **no** deberían fallar con el código actual (el string literal ya vale "expenses"/"invoices" hoy) — son de caracterización, para tener cobertura de regresión antes de tocar el controller. Confírmalo en el siguiente paso.

- [ ] **Step 2: Run tests to verify they currently pass (baseline), then verify TableSources exists**

Run: `mix test apps/conta_web/test/conta_web/controllers/expense_controller_test.exs apps/conta_web/test/conta_web/controllers/invoice_controller_test.exs`
Expected: PASS (comportamiento de hoy, con el string literal). Esto confirma la baseline antes del refactor.

- [ ] **Step 3: Refactor the controllers to use the registry**

En `apps/conta_web/lib/conta_web/controllers/expense_controller.ex`, añadir el alias y sustituir la línea 37:

```elixir
  alias Conta.Automator
  alias Conta.Automator.TableSources
  alias Conta.Book
```

```elixir
    expenses = Book.list_simple_expenses_filtered(filters)
    params = %{TableSources.expenses_key() => expenses}
```

En `apps/conta_web/lib/conta_web/controllers/invoice_controller.ex`, añadir el alias y sustituir la línea 79:

```elixir
  alias Conta.Automator
  alias Conta.Automator.TableSources
  alias Conta.Book
```

```elixir
    invoices = Book.list_invoices_filtered(filters)
    params = %{TableSources.invoices_key() => invoices}
```

- [ ] **Step 4: Run tests to verify they still pass**

Run: `mix test apps/conta_web/test/conta_web/controllers/expense_controller_test.exs apps/conta_web/test/conta_web/controllers/invoice_controller_test.exs`
Expected: PASS — mismo comportamiento observable, ahora sin el string literal duplicado.

- [ ] **Step 5: Commit**

```bash
git add apps/conta_web/lib/conta_web/controllers/expense_controller.ex \
        apps/conta_web/lib/conta_web/controllers/invoice_controller.ex \
        apps/conta_web/test/conta_web/controllers/expense_controller_test.exs \
        apps/conta_web/test/conta_web/controllers/invoice_controller_test.exs
git commit -m "Use Conta.Automator.TableSources canonical keys in export controllers"
```

---

### Task 6: Botón "Load real data" en `test_param_input`

**Files:**
- Modify: `apps/conta_web/lib/conta_web/components/automator_components.ex:59-72,114-123`
- Test: `apps/conta_web/test/conta_web/components/automator_components_test.exs` (nuevo)

- [ ] **Step 1: Write the failing test**

```elixir
defmodule ContaWeb.AutomatorComponentsTest do
  use ContaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Conta.Command.SetFilter
  alias ContaWeb.AutomatorComponents

  describe "test_param_input/1 for a :table param" do
    test "prefills the textarea with the given value" do
      param = %SetFilter.Param{name: "expenses", type: :table}

      html =
        render_component(&AutomatorComponents.test_param_input/1,
          param: param,
          value: ~s([{"a":1}])
        )

      assert html =~ ~s([{"a":1}])
    end

    test "renders a Load real data button wired to load_table_sample" do
      param = %SetFilter.Param{name: "expenses", type: :table}

      html = render_component(&AutomatorComponents.test_param_input/1, param: param, value: nil)

      assert html =~ "Load real data"
      assert html =~ ~s(phx-click="load_table_sample")
      assert html =~ ~s(phx-value-param="expenses")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test apps/conta_web/test/conta_web/components/automator_components_test.exs`
Expected: FAIL — `test_param_input/1` no acepta el assign `:value` (hoy solo declara `attr :param`), y no hay botón "Load real data" en el HTML.

- [ ] **Step 3: Write minimal implementation**

En `apps/conta_web/lib/conta_web/components/automator_components.ex`, añadir el import del botón compartido justo debajo de los `use` existentes (línea 7):

```elixir
  use Phoenix.Component
  use Gettext, backend: ContaWeb.Gettext

  import ContaWeb.CoreComponents, only: [button: 1]
```

Sustituir el bloque `attr :param` / `def test_param_input` (líneas 59-72):

```elixir
  attr :param, :any, required: true
  attr :value, :string, default: nil

  def test_param_input(assigns) do
    assigns = assign(assigns, :id, "test_params_#{assigns.param.name}")

    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span class="label mb-1">{@param.name}</span>
        {render_control(assigns)}
      </label>
    </div>
    """
  end
```

Sustituir la cláusula `:table` de `render_control` (líneas 114-123):

```elixir
  defp render_control(%{param: %{type: :table}} = assigns) do
    ~H"""
    <div class="flex gap-2 items-start">
      <textarea
        id={@id}
        name={"test_params[#{@param.name}]"}
        class="w-full textarea textarea-bordered"
        rows="3"
      ><%= @value %></textarea>
      <.button type="button" phx-click="load_table_sample" phx-value-param={@param.name} class="btn-sm">
        {gettext("Load real data")}
      </.button>
    </div>
    """
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test apps/conta_web/test/conta_web/components/automator_components_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add apps/conta_web/lib/conta_web/components/automator_components.ex \
        apps/conta_web/test/conta_web/components/automator_components_test.exs
git commit -m "Add Load real data button and value prefill to test_param_input"
```

---

### Task 7: `load_table_sample` en `FilterLive.Form` y `ShortcutLive.Form`

**Files:**
- Modify: `apps/conta_web/lib/conta_web/live/filter_live/form.ex:1-16,96-106`
- Modify: `apps/conta_web/lib/conta_web/live/filter_live/form.html.heex:67`
- Modify: `apps/conta_web/lib/conta_web/live/shortcut_live/form.ex:1-16,96-106`
- Modify: `apps/conta_web/lib/conta_web/live/shortcut_live/form.html.heex:53`
- Test: `apps/conta_web/test/conta_web/live/filter_live_test.exs`
- Test: `apps/conta_web/test/conta_web/live/shortcut_live_test.exs`

- [ ] **Step 1: Write the failing tests**

En `apps/conta_web/test/conta_web/live/filter_live_test.exs`, dentro de `describe "Form"` (después del test `"test-runs the Lua code without dispatching anything"`, línea ~98):

```elixir
    test "loads a real data sample for a table param", %{conn: conn, user: user} do
      insert(:invoice, %{invoice_number: "2023-00001"})
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/new")

      form_live
      |> form("#filter-form", set_filter: %{name: "invoice filter", output: "json"})
      |> render_change()

      form_live |> element("button", "Add parameter") |> render_click()

      form_live
      |> form("#filter-form", set_filter: %{params: %{"0" => %{"name" => "invoices", "type" => "table"}}})
      |> render_change()

      html = form_live |> element(~s(button[phx-click="load_table_sample"])) |> render_click()

      assert html =~ "2023-00001"
    end
```

(Añade `import Conta.BookFixtures` a la cabecera del fichero de test, para poder usar `insert(:invoice, ...)`.)

En `apps/conta_web/test/conta_web/live/shortcut_live_test.exs`, añade el mismo tipo de test (revisa primero el fichero para replicar exactamente sus imports/aliases y el nombre del formulario `#shortcut-form`, siguiendo el mismo patrón que `filter_live_test.exs`).

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test apps/conta_web/test/conta_web/live/filter_live_test.exs apps/conta_web/test/conta_web/live/shortcut_live_test.exs`
Expected: FAIL — no existe el evento `load_table_sample` en el servidor (`(FunctionClauseError)` o el botón no aparece porque el textarea sigue vacío tras el click, dependiendo de qué falle primero).

- [ ] **Step 3: Write minimal implementation**

En `apps/conta_web/lib/conta_web/live/filter_live/form.ex`, añadir el alias (junto a `alias Conta.Command.SetFilter`, línea 11):

```elixir
  alias Conta.Automator
  alias Conta.Automator.TableSources
  alias Conta.Command.SetFilter
```

Y el nuevo `handle_event`, justo después de `handle_event("test_run", ...)` (después de la línea 106):

```elixir
  def handle_event("load_table_sample", %{"param" => name}, socket) do
    param = Enum.find(socket.assigns.params_defs, &(&1.name == name))
    limit = (param && param.sample_limit) || TableSources.default_sample_limit()

    case TableSources.sample(name, limit) do
      {:error, :unknown_source} ->
        {:noreply, put_flash(socket, :error, gettext("Unknown data source"))}

      sample ->
        json = Jason.encode!(sample, pretty: true)

        form_params =
          Map.update(socket.assigns.form_params, "test_params", %{name => json}, &Map.put(&1, name, json))

        {:noreply, assign(socket, :form_params, form_params)}
    end
  end
```

En `apps/conta_web/lib/conta_web/live/filter_live/form.html.heex:67`, sustituir:

```heex
      <.test_param_input :for={param <- @params_defs} param={param} />
```

por:

```heex
      <.test_param_input
        :for={param <- @params_defs}
        param={param}
        value={get_in(@form_params, ["test_params", param.name])}
      />
```

Repite los mismos 3 cambios (alias, `handle_event`, `value={...}` en el heex) en `apps/conta_web/lib/conta_web/live/shortcut_live/form.ex` y `form.html.heex:53`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test apps/conta_web/test/conta_web/live/filter_live_test.exs apps/conta_web/test/conta_web/live/shortcut_live_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add apps/conta_web/lib/conta_web/live/filter_live/form.ex apps/conta_web/lib/conta_web/live/filter_live/form.html.heex \
        apps/conta_web/lib/conta_web/live/shortcut_live/form.ex apps/conta_web/lib/conta_web/live/shortcut_live/form.html.heex \
        apps/conta_web/test/conta_web/live/filter_live_test.exs apps/conta_web/test/conta_web/live/shortcut_live_test.exs
git commit -m "Wire the Load real data button to Conta.Automator.TableSources"
```

---

### Task 8: Restringir `name` y añadir "Sample size" en el editor de parámetros

**Files:**
- Modify: `apps/conta_web/lib/conta_web/live/filter_live/form.html.heex:39-48`
- Modify: `apps/conta_web/lib/conta_web/live/shortcut_live/form.html.heex:22-31`
- Modify: `apps/conta_web/lib/conta_web/live/filter_live/form.ex` (alias `TableSources`, ya añadido en Task 7)
- Modify: `apps/conta_web/lib/conta_web/live/shortcut_live/form.ex` (idem)
- Test: `apps/conta_web/test/conta_web/live/filter_live_test.exs`
- Test: `apps/conta_web/test/conta_web/live/shortcut_live_test.exs`

- [ ] **Step 1: Write the failing test**

En `apps/conta_web/test/conta_web/live/filter_live_test.exs`, dentro de `describe "Form"`:

```elixir
    test "restricts the parameter name to known table sources when type is table", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/new")

      form_live |> element("button", "Add parameter") |> render_click()

      html =
        form_live
        |> form("#filter-form", set_filter: %{params: %{"0" => %{"type" => "table"}}})
        |> render_change()

      assert html =~ ~s(<option value="expenses">Expenses</option>)
      assert html =~ ~s(<option value="invoices">Invoices</option>)
      assert html =~ "Sample size"
    end

    test "keeps the table select+sample-size UI when editing a sibling field on an already-saved table param",
         %{conn: conn, user: user} do
      filter =
        insert(:filter, %{
          params: [build(:filter_param, %{name: "expenses", type: :table, sample_limit: 5})]
        })

      conn = log_in_user(conn, user)
      {:ok, form_live, _html} = live(conn, ~p"/automation/filters/#{filter}/edit")

      # Regression for the bug the plan reviewer found: editing a *sibling* field
      # (sample_limit here) without touching the `type` select itself must not
      # flip `p[:type].value` back to a raw string that fails an atom comparison
      # and silently reverts the row to the free-text Name/Options layout.
      html =
        form_live
        |> form("#filter-form", set_filter: %{params: %{"0" => %{"sample_limit" => "8"}}})
        |> render_change()

      assert html =~ ~s(<option value="expenses">Expenses</option>)
      assert html =~ ~s(<option value="invoices">Invoices</option>)
      assert html =~ "Sample size"
    end
```

Replica los dos tests análogos en `shortcut_live_test.exs` contra `#shortcut-form` (usa `insert(:shortcut, ...)` con `build(:shortcut_param, ...)` para el segundo).

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test apps/conta_web/test/conta_web/live/filter_live_test.exs apps/conta_web/test/conta_web/live/shortcut_live_test.exs`
Expected: FAIL en los 4 tests nuevos (2 por fichero) — hoy `name` siempre es un `<input>` de texto libre, no existe el campo "Sample size", y por tanto tampoco existe aún el bug de la comparación por átomo (ese solo aparecería si se implementara con `p[:type].value == :table` en vez de `to_string(...)`).

- [ ] **Step 3: Write minimal implementation**

En `apps/conta_web/lib/conta_web/live/filter_live/form.html.heex:39-48`, sustituir el bloque `<.inputs_for :let={p} field={@form[:params]}>` por:

```heex
        <.inputs_for :let={p} field={@form[:params]}>
          <div class="grid grid-cols-[1fr_1fr_1fr_auto] gap-2 items-end mb-2">
            <%= if to_string(p[:type].value) == "table" do %>
              <.input field={p[:name]} type="select" label={gettext("Name")} options={TableSources.options()} />
            <% else %>
              <.input field={p[:name]} label={gettext("Name")} />
            <% end %>
            <.input field={p[:type]} type="select" label={gettext("Type")} options={param_type_options()} />
            <%= if to_string(p[:type].value) == "table" do %>
              <.input
                field={p[:sample_limit]}
                type="number"
                label={gettext("Sample size")}
                value={p[:sample_limit].value || TableSources.default_sample_limit()}
              />
            <% else %>
              <.input field={p[:options]} label={gettext("Options (comma separated)")} />
            <% end %>
            <.button type="button" phx-click="del_param" phx-value-index={p.index} class="btn-sm btn-error">
              {gettext("Remove")}
            </.button>
          </div>
        </.inputs_for>
```

**Importante:** la comparación usa `to_string(p[:type].value) == "table"`, no `p[:type].value == :table`. Para una fila **ya existente** (modo edición, `Command.SetFilter.Param`/`SetShortcut.Param` tienen `id` autogenerado a diferencia de los `Param` de evento/proyector), si el usuario edita un campo hermano (p. ej. "Sample size" u "Options") sin tocar el propio `<select>` de `type` en esa misma petición, `phoenix_ecto` resuelve `p[:type].value` al **string crudo** `"table"` en vez de al átomo `:table` (el cast normal solo ocurre cuando el campo `type` en sí cambió respecto a los datos ya persistidos). Comparar contra el átomo directamente rompería la edición de un parámetro `table` ya guardado en cuanto se tocase cualquier otro campo de esa fila — `to_string/1` cubre ambos casos sin ambigüedad.
```

Aplica el mismo cambio de estructura en `apps/conta_web/lib/conta_web/live/shortcut_live/form.html.heex:22-31` (el `grid-cols` ya es `[1fr_1fr_1fr_auto]` en ambos ficheros, no hace falta tocarlo).

El alias `TableSources` en ambos `.ex` ya se añadió en la Task 7 — confirma que sigue ahí (no hay paso adicional).

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test apps/conta_web/test/conta_web/live/filter_live_test.exs apps/conta_web/test/conta_web/live/shortcut_live_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add apps/conta_web/lib/conta_web/live/filter_live/form.html.heex \
        apps/conta_web/lib/conta_web/live/shortcut_live/form.html.heex \
        apps/conta_web/test/conta_web/live/filter_live_test.exs apps/conta_web/test/conta_web/live/shortcut_live_test.exs
git commit -m "Restrict table param name to TableSources registry, add sample size field"
```

---

### Task 9: Verificación final

**Files:** ninguno (solo verificación)

- [ ] **Step 1: Run the full test suite**

Run: `mix test`
Expected: PASS, 0 failures.

- [ ] **Step 2: Compile with warnings as errors to catch unused aliases/typos**

Run: `mix compile --force --warnings-as-errors`
Expected: compila sin warnings.

- [ ] **Step 3: Manual smoke test (opcional pero recomendado)**

Arranca el servidor (`mix phx.server`), entra en `/automation/filters/new`, añade un parámetro, cambia su tipo a "table", confirma que "Name" pasa a desplegable con "Expenses"/"Invoices" y aparece "Sample size". Guarda un filtro con `name: "expenses"`, tipo `table`, código `return #expenses`, ve al panel "Test data" y pulsa "Load real data" — confirma que el textarea se rellena con JSON real (o `[]` si no hay expenses en la base de datos de desarrollo).

- [ ] **Step 4: Final commit (si el Step 3 reveló algún ajuste)**

Si el smoke test no revela cambios, no hay nada que commitear en este paso — las Tasks 1-8 ya dejaron el trabajo completo y commiteado.
