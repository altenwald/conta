# Conciliación bancaria — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Importar extractos bancarios en CSV a través de importadores Lua (estilo Shortcuts), cotejarlos contra reglas de concordancia dentro de un nuevo aggregate `Reconciliation`, y confirmarlos (individualmente o en bloque) para convertirlos en transacciones reales del ledger, sin arriesgar transacciones duplicadas ni perder movimientos.

**Architecture:** Nuevo aggregate singleton `Reconciliation` (Commanded, mismo patrón que `Automator`/`Ledger`) que mantiene en su propio estado event-sourced tanto las reglas de match como los movimientos pendientes — necesario porque la evaluación de reglas debe ser determinista dentro del `execute/2` del aggregate, no una consulta a la base de datos de lectura. La confirmación (crear la transacción real y retirar el movimiento) se orquesta de forma síncrona en la capa de contexto (`Conta.Reconciliation.confirm_movement/1`), nunca dentro de un aggregate ni con un Process Manager — ver spec para la justificación. Importadores son una tercera variante de entidad Automation junto a Shortcut/Filter, reutilizando el motor Lua existente.

**Tech Stack:** Elixir, Phoenix LiveView, Commanded (CQRS/ES), Ecto/PostgreSQL, `:luerl` (Lua), NimbleCSV (nuevo).

**Spec:** `docs/superpowers/specs/2026-07-11-bank-reconciliation-design.md` — leer antes de ejecutar este plan; contiene el razonamiento detrás de cada decisión (por qué no hay Process Manager, la convención de signo debe/haber, el flag `transacted`, etc.).

---

## Cómo usar este plan

Cada fase se corresponde con una de las 6 fases TDD acordadas en el spec. Las Fases 1 y 2 (aggregate + orquestación de confirmación) son el núcleo de negocio y llevan el mayor detalle: código completo, tests exactos, pasos de 2-5 minutos. Las Fases 3-6 (UI) siguen la misma granularidad de tareas pero se apoyan explícitamente en los ficheros ya existentes (`shortcut_live/`, `filter_live/`, `entry_live/form_component/account_transaction.ex`) como plantilla a copiar y adaptar — se referencian con ruta y rango de líneas en vez de reproducir HEEx completo cuando es puro boilerplate ya visto en el codebase.

Ejecutar las fases en orden: cada una depende de la anterior.

---

# FASE 1 — Aggregate `Reconciliation` (núcleo)

## Task 1: Comando `SetMatchRule`

**Files:**
- Create: `apps/conta/lib/conta/command/set_match_rule.ex`
- Test: `apps/conta/test/conta/command/set_match_rule_test.exs`

- [x] **Step 1: Escribir el test que falla**

```elixir
defmodule Conta.Command.SetMatchRuleTest do
  use ExUnit.Case

  alias Conta.Command.SetMatchRule

  describe "changeset/2" do
    test "valid with one condition" do
      params = %{
        "name" => "Netflix",
        "conditions" => [%{"field" => "description", "comparator" => "contains", "value" => "NETFLIX"}],
        "match_type" => "all",
        "account_name" => ["Expenses", "Subscriptions"]
      }

      changeset = SetMatchRule.changeset(params)
      assert changeset.valid?
    end

    test "invalid without conditions" do
      params = %{"name" => "Netflix", "conditions" => [], "match_type" => "all", "account_name" => ["Expenses"]}
      changeset = SetMatchRule.changeset(params)
      refute changeset.valid?
      assert %{conditions: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid comparator for amount field" do
      params = %{
        "name" => "x",
        "conditions" => [%{"field" => "amount", "comparator" => "contains", "value" => "10"}],
        "match_type" => "all",
        "account_name" => ["Expenses"]
      }

      changeset = SetMatchRule.changeset(params)
      refute changeset.valid?
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
```

- [x] **Step 2: Ejecutar y comprobar que falla**

Run: `cd apps/conta && mix test test/conta/command/set_match_rule_test.exs`
Expected: FAIL — `Conta.Command.SetMatchRule` no existe.

- [x] **Step 3: Implementar el comando**

```elixir
defmodule Conta.Command.SetMatchRule do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  @description_comparators ~w[contains equals regex]a
  @amount_comparators ~w[equals greater_than less_than]a
  @on_date_comparators ~w[equals between]a

  typed_embedded_schema do
    field :id, :binary_id
    field :reconciliation, :string, default: "default"
    field :name, :string

    embeds_many :conditions, Condition do
      field :field, Ecto.Enum, values: ~w[description amount on_date]a
      field :comparator, Ecto.Enum, values: ~w[contains equals regex greater_than less_than between]a
      field :value, :string
      field :value_to, :string
    end

    field :match_type, Ecto.Enum, values: ~w[all any]a, default: :all
    field :account_name, {:array, :string}
  end

  @required_fields ~w[name match_type account_name]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields)
    |> cast_embed(:conditions, with: &changeset_condition/2, required: true)
    |> validate_required(@required_fields)
    |> validate_length(:conditions, min: 1)
  end

  @required_fields ~w[field comparator value]a
  @optional_fields ~w[value_to]a

  @doc false
  def changeset_condition(model, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_comparator()
  end

  defp validate_comparator(changeset) do
    field = get_field(changeset, :field)
    comparator = get_field(changeset, :comparator)

    valid_comparators =
      case field do
        :description -> @description_comparators
        :amount -> @amount_comparators
        :on_date -> @on_date_comparators
        _ -> []
      end

    if comparator in valid_comparators do
      changeset
    else
      add_error(changeset, :comparator, "is not valid for field #{field}")
    end
  end

  def to_command(changeset) do
    apply_changes(changeset)
  end
end
```

- [x] **Step 4: Ejecutar y comprobar que pasa**

Run: `cd apps/conta && mix test test/conta/command/set_match_rule_test.exs`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git add apps/conta/lib/conta/command/set_match_rule.ex apps/conta/test/conta/command/set_match_rule_test.exs
git commit -m "feat: add SetMatchRule command"
```

## Task 2: Comandos `RemoveMatchRule` y `ReorderMatchRules`

**Files:**
- Create: `apps/conta/lib/conta/command/remove_match_rule.ex`
- Create: `apps/conta/lib/conta/command/reorder_match_rules.ex`

No requieren test propio (son `typed_embedded_schema` sin `changeset/2`, igual que `RemoveShortcut` — su validación ocurre en el aggregate).

- [x] **Step 1: Implementar `RemoveMatchRule`**

```elixir
defmodule Conta.Command.RemoveMatchRule do
  use TypedEctoSchema

  @primary_key false

  typed_embedded_schema do
    field :id, :binary_id
    field :reconciliation, :string, default: "default"
  end
end
```

- [x] **Step 2: Implementar `ReorderMatchRules`**

```elixir
defmodule Conta.Command.ReorderMatchRules do
  use TypedEctoSchema

  @primary_key false

  typed_embedded_schema do
    field :ids, {:array, :binary_id}
    field :reconciliation, :string, default: "default"
  end
end
```

- [x] **Step 3: Commit**

```bash
git add apps/conta/lib/conta/command/remove_match_rule.ex apps/conta/lib/conta/command/reorder_match_rules.ex
git commit -m "feat: add RemoveMatchRule and ReorderMatchRules commands"
```

## Task 3: Eventos de reglas de match

**Files:**
- Create: `apps/conta/lib/conta/event/match_rule_set.ex`
- Create: `apps/conta/lib/conta/event/match_rule_removed.ex`
- Create: `apps/conta/lib/conta/event/match_rules_reordered.ex`

- [x] **Step 1: Implementar `MatchRuleSet`** (mismo shape que `SetMatchRule` + `get_result` para producir directamente struct o `{:error, _}`, como `ShortcutSet`)

```elixir
defmodule Conta.Event.MatchRuleSet do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :id, :binary_id
    field :name, :string

    embeds_many :conditions, Condition, primary_key: false, on_replace: :delete do
      field :field, Ecto.Enum, values: ~w[description amount on_date]a
      field :comparator, Ecto.Enum, values: ~w[contains equals regex greater_than less_than between]a
      field :value, :string
      field :value_to, :string
    end

    field :match_type, Ecto.Enum, values: ~w[all any]a, default: :all
    field :account_name, {:array, :string}
  end

  @required_fields ~w[id name match_type account_name]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields)
    |> cast_embed(:conditions, with: &changeset_condition/2)
    |> validate_required(@required_fields)
    |> get_result()
  end

  @required_fields ~w[field comparator value]a
  @optional_fields ~w[value_to]a

  @doc false
  def changeset_condition(model, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Jason.Encoder, for: Conta.Event.MatchRuleSet.Condition do
  def encode(condition, _opts) do
    Jason.encode!(Map.from_struct(condition))
  end
end
```

- [x] **Step 2: Implementar `MatchRuleRemoved`**

```elixir
defmodule Conta.Event.MatchRuleRemoved do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :id, :binary_id
  end

  @fields ~w[id]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @fields)
    |> validate_required(@fields)
    |> get_result()
  end
end
```

- [x] **Step 3: Implementar `MatchRulesReordered`**

```elixir
defmodule Conta.Event.MatchRulesReordered do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :ids, {:array, :binary_id}
  end

  @fields ~w[ids]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @fields)
    |> validate_required(@fields)
    |> get_result()
  end
end
```

- [x] **Step 4: Commit**

```bash
git add apps/conta/lib/conta/event/match_rule_set.ex apps/conta/lib/conta/event/match_rule_removed.ex apps/conta/lib/conta/event/match_rules_reordered.ex
git commit -m "feat: add match rule events"
```

## Task 4: Comandos de movimientos

**Files:**
- Create: `apps/conta/lib/conta/command/import_movements.ex`
- Create: `apps/conta/lib/conta/command/update_movement.ex`
- Create: `apps/conta/lib/conta/command/remove_movement.ex`
- Create: `apps/conta/lib/conta/command/mark_movement_transacted.ex`

- [x] **Step 1: Implementar `ImportMovements`**

```elixir
defmodule Conta.Command.ImportMovements do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  typed_embedded_schema do
    field :reconciliation, :string, default: "default"

    embeds_many :movements, Movement, primary_key: false do
      field :on_date, :date
      field :description, :string
      field :amount, :integer
      field :currency, Money.Ecto.Currency.Type
      field :asset_account_name, {:array, :string}
      field :source, :string
    end
  end

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, [:reconciliation])
    |> cast_embed(:movements, with: &changeset_movement/2, required: true)
  end

  @required_fields ~w[on_date description amount currency asset_account_name]a
  @optional_fields ~w[source]a

  @doc false
  def changeset_movement(model, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  def to_command(changeset) do
    apply_changes(changeset)
  end
end
```

- [x] **Step 2: Implementar `UpdateMovement`**

El comando lleva `changes` como mapa libre (no un embedded schema) porque es una edición parcial: solo las claves presentes se aplican, y el aggregate necesita distinguir "el usuario no tocó este campo" de "el usuario lo puso a `nil`" — un embedded schema con todos los campos opcionales no permite esa distinción sin trabajo extra.

```elixir
defmodule Conta.Command.UpdateMovement do
  use TypedEctoSchema

  @primary_key false

  typed_embedded_schema do
    field :id, :binary_id
    field :changes, :map
    field :reconciliation, :string, default: "default"
  end
end
```

- [x] **Step 3: Implementar `RemoveMovement`**

```elixir
defmodule Conta.Command.RemoveMovement do
  use TypedEctoSchema

  @primary_key false

  typed_embedded_schema do
    field :id, :binary_id
    field :reconciliation, :string, default: "default"
  end
end
```

- [x] **Step 4: Implementar `MarkMovementTransacted`**

```elixir
defmodule Conta.Command.MarkMovementTransacted do
  use TypedEctoSchema

  @primary_key false

  typed_embedded_schema do
    field :id, :binary_id
    field :reconciliation, :string, default: "default"
  end
end
```

- [x] **Step 5: Commit**

```bash
git add apps/conta/lib/conta/command/import_movements.ex apps/conta/lib/conta/command/update_movement.ex apps/conta/lib/conta/command/remove_movement.ex apps/conta/lib/conta/command/mark_movement_transacted.ex
git commit -m "feat: add movement commands"
```

## Task 5: Eventos de movimientos

**Files:**
- Create: `apps/conta/lib/conta/event/movements_imported.ex`
- Create: `apps/conta/lib/conta/event/movement_updated.ex`
- Create: `apps/conta/lib/conta/event/movement_removed.ex`
- Create: `apps/conta/lib/conta/event/movement_transacted.ex`

- [x] **Step 1: Implementar `MovementsImported`**

Cada movimiento importado ya lleva su `id` generado y su `account_name` propuesto (o `nil`) — ambos calculados por el aggregate en `execute/2` antes de construir el evento, así el evento es el registro completo y determinista de lo que ocurrió (no hace falta recalcular el matching al reproducir eventos).

```elixir
defmodule Conta.Event.MovementsImported do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    embeds_many :movements, Movement, primary_key: false, on_replace: :delete do
      field :id, :binary_id
      field :on_date, :date
      field :description, :string
      field :amount, :integer
      field :currency, Money.Ecto.Currency.Type
      field :asset_account_name, {:array, :string}
      field :account_name, {:array, :string}
      field :source, :string
      field :transacted, :boolean, default: false
    end
  end

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, [])
    |> cast_embed(:movements, with: &changeset_movement/2)
    |> get_result()
  end

  @required_fields ~w[id on_date description amount currency asset_account_name transacted]a
  @optional_fields ~w[account_name source]a

  @doc false
  def changeset_movement(model, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Jason.Encoder, for: Conta.Event.MovementsImported.Movement do
  def encode(movement, _opts) do
    Jason.encode!(Map.from_struct(movement))
  end
end
```

- [x] **Step 2: Implementar `MovementUpdated`**

```elixir
defmodule Conta.Event.MovementUpdated do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :id, :binary_id
    field :on_date, :date
    field :description, :string
    field :amount, :integer
    field :currency, Money.Ecto.Currency.Type
    field :account_name, {:array, :string}
  end

  @fields ~w[id on_date description amount currency account_name]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @fields)
    |> validate_required([:id])
    |> get_result()
  end
end
```

- [x] **Step 3: Implementar `MovementRemoved`**

```elixir
defmodule Conta.Event.MovementRemoved do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :id, :binary_id
  end

  @fields ~w[id]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @fields)
    |> validate_required(@fields)
    |> get_result()
  end
end
```

- [x] **Step 4: Implementar `MovementTransacted`**

```elixir
defmodule Conta.Event.MovementTransacted do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :id, :binary_id
  end

  @fields ~w[id]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @fields)
    |> validate_required(@fields)
    |> get_result()
  end
end
```

- [x] **Step 5: Commit**

```bash
git add apps/conta/lib/conta/event/movements_imported.ex apps/conta/lib/conta/event/movement_updated.ex apps/conta/lib/conta/event/movement_removed.ex apps/conta/lib/conta/event/movement_transacted.ex
git commit -m "feat: add movement events"
```

## Task 6: Aggregate `Reconciliation` — struct y reglas de match

**Files:**
- Create: `apps/conta/lib/conta/aggregate/reconciliation.ex`
- Test: `apps/conta/test/aggregate/reconciliation_test.exs`

- [x] **Step 1: Escribir los tests que fallan (reglas de match)**

```elixir
defmodule Conta.Aggregate.ReconciliationTest do
  use ExUnit.Case

  alias Conta.Aggregate.Reconciliation

  alias Conta.Command.RemoveMatchRule
  alias Conta.Command.ReorderMatchRules
  alias Conta.Command.SetMatchRule

  alias Conta.Event.MatchRuleRemoved
  alias Conta.Event.MatchRuleSet
  alias Conta.Event.MatchRulesReordered

  describe "match rules" do
    test "create a new rule successfully" do
      reconciliation = %Reconciliation{}

      command = %SetMatchRule{
        name: "Netflix",
        conditions: [%SetMatchRule.Condition{field: :description, comparator: :contains, value: "NETFLIX"}],
        match_type: :all,
        account_name: ["Expenses", "Subscriptions"]
      }

      event = Reconciliation.execute(reconciliation, command)

      assert %MatchRuleSet{name: "Netflix", match_type: :all, account_name: ["Expenses", "Subscriptions"]} = event
      refute is_nil(event.id)

      reconciliation = Reconciliation.apply(reconciliation, event)
      assert [%{id: id, name: "Netflix"}] = reconciliation.match_rules
      assert id == event.id
    end

    test "update an existing rule preserves its position" do
      rule_a = %{id: Ecto.UUID.generate(), name: "A", conditions: [], match_type: :all, account_name: ["X"]}
      rule_b = %{id: Ecto.UUID.generate(), name: "B", conditions: [], match_type: :all, account_name: ["Y"]}
      reconciliation = %Reconciliation{match_rules: [rule_a, rule_b]}

      command = %SetMatchRule{
        id: rule_a.id,
        name: "A renamed",
        conditions: [%SetMatchRule.Condition{field: :description, comparator: :equals, value: "x"}],
        match_type: :all,
        account_name: ["X"]
      }

      event = Reconciliation.execute(reconciliation, command)
      reconciliation = Reconciliation.apply(reconciliation, event)

      assert [%{id: id_a, name: "A renamed"}, %{id: id_b, name: "B"}] = reconciliation.match_rules
      assert id_a == rule_a.id
      assert id_b == rule_b.id
    end

    test "remove a rule" do
      rule = %{id: Ecto.UUID.generate(), name: "A", conditions: [], match_type: :all, account_name: ["X"]}
      reconciliation = %Reconciliation{match_rules: [rule]}

      event = Reconciliation.execute(reconciliation, %RemoveMatchRule{id: rule.id})
      assert %MatchRuleRemoved{id: id} = event
      assert id == rule.id

      reconciliation = Reconciliation.apply(reconciliation, event)
      assert [] == reconciliation.match_rules
    end

    test "removing an unknown rule returns an error" do
      reconciliation = %Reconciliation{match_rules: []}
      assert {:error, %{id: ["not found"]}} = Reconciliation.execute(reconciliation, %RemoveMatchRule{id: Ecto.UUID.generate()})
    end

    test "reorder rules" do
      rule_a = %{id: Ecto.UUID.generate(), name: "A", conditions: [], match_type: :all, account_name: ["X"]}
      rule_b = %{id: Ecto.UUID.generate(), name: "B", conditions: [], match_type: :all, account_name: ["Y"]}
      reconciliation = %Reconciliation{match_rules: [rule_a, rule_b]}

      event = Reconciliation.execute(reconciliation, %ReorderMatchRules{ids: [rule_b.id, rule_a.id]})
      assert %MatchRulesReordered{ids: [id_b, id_a]} = event

      reconciliation = Reconciliation.apply(reconciliation, event)
      assert [%{id: ^id_b}, %{id: ^id_a}] = reconciliation.match_rules
    end

    test "reordering with a mismatched set of ids returns an error" do
      rule_a = %{id: Ecto.UUID.generate(), name: "A", conditions: [], match_type: :all, account_name: ["X"]}
      reconciliation = %Reconciliation{match_rules: [rule_a]}

      assert {:error, %{ids: ["must match existing rule ids"]}} =
               Reconciliation.execute(reconciliation, %ReorderMatchRules{ids: [Ecto.UUID.generate()]})
    end
  end
end
```

- [x] **Step 2: Ejecutar y comprobar que falla**

Run: `cd apps/conta && mix test test/aggregate/reconciliation_test.exs`
Expected: FAIL — `Conta.Aggregate.Reconciliation` no existe.

- [x] **Step 3: Implementar el aggregate (struct + reglas de match)**

```elixir
defmodule Conta.Aggregate.Reconciliation do
  alias Conta.Command.RemoveMatchRule
  alias Conta.Command.ReorderMatchRules
  alias Conta.Command.SetMatchRule

  alias Conta.Event.MatchRuleRemoved
  alias Conta.Event.MatchRuleSet
  alias Conta.Event.MatchRulesReordered

  @derive Jason.Encoder

  @type match_rule() :: %{
          id: String.t(),
          name: String.t(),
          conditions: list(),
          match_type: :all | :any,
          account_name: [String.t()]
        }

  @type movement() :: map()

  @type t() :: %__MODULE__{
          match_rules: [match_rule()],
          movements: %{String.t() => movement()}
        }
  defstruct match_rules: [],
            movements: %{}

  def execute(%__MODULE__{}, %SetMatchRule{id: nil} = command) do
    build_match_rule_set(command, Ecto.UUID.generate())
  end

  def execute(%__MODULE__{}, %SetMatchRule{} = command) do
    build_match_rule_set(command, command.id)
  end

  def execute(%__MODULE__{match_rules: match_rules}, %RemoveMatchRule{id: id} = command) do
    if Enum.any?(match_rules, &(&1.id == id)) do
      command
      |> Map.from_struct()
      |> MatchRuleRemoved.changeset()
    else
      {:error, %{id: ["not found"]}}
    end
  end

  def execute(%__MODULE__{match_rules: match_rules}, %ReorderMatchRules{ids: ids}) do
    existing_ids = Enum.map(match_rules, & &1.id) |> MapSet.new()

    # Both checks are needed: the length check alone wouldn't catch a shuffled set
    # with a substituted id, and the MapSet check alone wouldn't catch a duplicate id
    # in `ids` that happens to keep the set size equal to `existing_ids`.
    if length(ids) == length(match_rules) and MapSet.new(ids) == existing_ids do
      %{ids: ids}
      |> MatchRulesReordered.changeset()
    else
      {:error, %{ids: ["must match existing rule ids"]}}
    end
  end

  defp build_match_rule_set(command, id) do
    command
    |> Map.from_struct()
    |> Map.put(:id, id)
    |> Map.update!(:conditions, fn conditions -> Enum.map(conditions, &Map.from_struct/1) end)
    |> MatchRuleSet.changeset()
  end

  def apply(%__MODULE__{match_rules: match_rules} = reconciliation, %MatchRuleSet{} = event) do
    rule = %{
      id: event.id,
      name: event.name,
      conditions: Enum.map(event.conditions, &Map.from_struct/1),
      match_type: event.match_type,
      account_name: event.account_name
    }

    match_rules =
      if Enum.any?(match_rules, &(&1.id == rule.id)) do
        Enum.map(match_rules, fn existing -> if existing.id == rule.id, do: rule, else: existing end)
      else
        match_rules ++ [rule]
      end

    %__MODULE__{reconciliation | match_rules: match_rules}
  end

  def apply(%__MODULE__{match_rules: match_rules} = reconciliation, %MatchRuleRemoved{id: id}) do
    %__MODULE__{reconciliation | match_rules: Enum.reject(match_rules, &(&1.id == id))}
  end

  def apply(%__MODULE__{match_rules: match_rules} = reconciliation, %MatchRulesReordered{ids: ids}) do
    by_id = Map.new(match_rules, &{&1.id, &1})
    %__MODULE__{reconciliation | match_rules: Enum.map(ids, &by_id[&1])}
  end

  def apply(reconciliation, _event), do: reconciliation
end
```

- [x] **Step 4: Ejecutar y comprobar que pasa**

Run: `cd apps/conta && mix test test/aggregate/reconciliation_test.exs`
Expected: PASS (6 tests)

- [x] **Step 5: Commit**

```bash
git add apps/conta/lib/conta/aggregate/reconciliation.ex apps/conta/test/aggregate/reconciliation_test.exs
git commit -m "feat: add Reconciliation aggregate with match rule commands"
```

## Task 7: Motor de evaluación de reglas + `ImportMovements`

**Files:**
- Modify: `apps/conta/lib/conta/aggregate/reconciliation.ex`
- Modify: `apps/conta/test/aggregate/reconciliation_test.exs`

- [x] **Step 1: Añadir los tests que fallan**

```elixir
  alias Conta.Command.ImportMovements
  alias Conta.Event.MovementsImported

  describe "import movements" do
    setup do
      netflix_rule = %{
        id: Ecto.UUID.generate(),
        name: "Netflix",
        conditions: [%{field: :description, comparator: :contains, value: "NETFLIX", value_to: nil}],
        match_type: :all,
        account_name: ["Expenses", "Subscriptions"]
      }

      %{reconciliation: %Reconciliation{match_rules: [netflix_rule]}, netflix_rule: netflix_rule}
    end

    test "a movement matching a rule gets account_name proposed", %{reconciliation: reconciliation} do
      command = %ImportMovements{
        movements: [
          %ImportMovements.Movement{
            on_date: ~D[2026-07-01],
            description: "NETFLIX.COM SUBSCRIPTION",
            amount: -1399,
            currency: :EUR,
            asset_account_name: ["Assets", "Bank"]
          }
        ]
      }

      event = Reconciliation.execute(reconciliation, command)

      assert %MovementsImported{movements: [movement]} = event
      assert movement.account_name == ["Expenses", "Subscriptions"]
      assert movement.description == "NETFLIX.COM SUBSCRIPTION"
      refute is_nil(movement.id)
      refute movement.transacted

      reconciliation = Reconciliation.apply(reconciliation, event)
      assert map_size(reconciliation.movements) == 1
      assert [{_id, %{account_name: ["Expenses", "Subscriptions"]}}] = Map.to_list(reconciliation.movements)
    end

    test "a movement matching no rule gets account_name nil", %{reconciliation: reconciliation} do
      command = %ImportMovements{
        movements: [
          %ImportMovements.Movement{
            on_date: ~D[2026-07-01],
            description: "UNKNOWN TRANSFER",
            amount: -4530,
            currency: :EUR,
            asset_account_name: ["Assets", "Bank"]
          }
        ]
      }

      assert %MovementsImported{movements: [%{account_name: nil}]} = Reconciliation.execute(reconciliation, command)
    end

    test "first matching rule wins when several would match", %{reconciliation: reconciliation, netflix_rule: netflix_rule} do
      second_rule = %{
        id: Ecto.UUID.generate(),
        name: "Also contains NETFLIX",
        conditions: [%{field: :description, comparator: :contains, value: "NETFLIX", value_to: nil}],
        match_type: :all,
        account_name: ["Expenses", "Other"]
      }

      reconciliation = %Reconciliation{match_rules: [netflix_rule, second_rule]}

      command = %ImportMovements{
        movements: [
          %ImportMovements.Movement{
            on_date: ~D[2026-07-01],
            description: "NETFLIX.COM",
            amount: -1399,
            currency: :EUR,
            asset_account_name: ["Assets", "Bank"]
          }
        ]
      }

      assert %MovementsImported{movements: [%{account_name: ["Expenses", "Subscriptions"]}]} =
               Reconciliation.execute(reconciliation, command)
    end

    test "match_type any requires only one condition to hold" do
      rule = %{
        id: Ecto.UUID.generate(),
        name: "big or Netflix",
        conditions: [
          %{field: :description, comparator: :contains, value: "NETFLIX", value_to: nil},
          %{field: :amount, comparator: :greater_than, value: "100000", value_to: nil}
        ],
        match_type: :any,
        account_name: ["Expenses", "Subscriptions"]
      }

      reconciliation = %Reconciliation{match_rules: [rule]}

      command = %ImportMovements{
        movements: [
          %ImportMovements.Movement{
            on_date: ~D[2026-07-01],
            description: "totally unrelated",
            amount: 200_000,
            currency: :EUR,
            asset_account_name: ["Assets", "Bank"]
          }
        ]
      }

      assert %MovementsImported{movements: [%{account_name: ["Expenses", "Subscriptions"]}]} =
               Reconciliation.execute(reconciliation, command)
    end

    test "on_date between condition" do
      rule = %{
        id: Ecto.UUID.generate(),
        name: "July",
        conditions: [%{field: :on_date, comparator: :between, value: "2026-07-01", value_to: "2026-07-31"}],
        match_type: :all,
        account_name: ["Expenses", "Misc"]
      }

      reconciliation = %Reconciliation{match_rules: [rule]}

      in_range = %ImportMovements.Movement{
        on_date: ~D[2026-07-15],
        description: "x",
        amount: -100,
        currency: :EUR,
        asset_account_name: ["Assets", "Bank"]
      }

      out_of_range = %ImportMovements.Movement{
        on_date: ~D[2026-08-01],
        description: "x",
        amount: -100,
        currency: :EUR,
        asset_account_name: ["Assets", "Bank"]
      }

      command = %ImportMovements{movements: [in_range, out_of_range]}

      assert %MovementsImported{movements: [matched, unmatched]} = Reconciliation.execute(reconciliation, command)
      assert matched.account_name == ["Expenses", "Misc"]
      assert is_nil(unmatched.account_name)
    end
  end
```

- [x] **Step 2: Ejecutar y comprobar que falla**

Run: `cd apps/conta && mix test test/aggregate/reconciliation_test.exs`
Expected: FAIL — no hay cláusula `execute/2` para `ImportMovements`.

- [x] **Step 3: Implementar `ImportMovements` y el motor de reglas**

Añadir a `apps/conta/lib/conta/aggregate/reconciliation.ex`:

```elixir
  alias Conta.Command.ImportMovements
  alias Conta.Event.MovementsImported

  # `MovementsImported.changeset/2` (Task 5) already ends its own pipeline with
  # `|> get_result()`, so it returns the resolved `%MovementsImported{}` struct or
  # `{:error, errors}` directly — piping that into `Conta.EctoHelpers.get_result/1`
  # again would raise, since `get_result/1` requires a raw `%Ecto.Changeset{}`, not an
  # already-resolved struct. Do not add a trailing `get_result()` call here.
  def execute(%__MODULE__{match_rules: match_rules}, %ImportMovements{movements: movements}) do
    movements =
      Enum.map(movements, fn movement ->
        movement
        |> Map.from_struct()
        |> Map.put(:id, Ecto.UUID.generate())
        |> Map.put(:account_name, evaluate_rules(match_rules, movement))
        |> Map.put(:transacted, false)
      end)

    %{movements: movements}
    |> MovementsImported.changeset()
  end

  defp evaluate_rules(match_rules, movement) do
    Enum.find_value(match_rules, fn rule ->
      if rule_matches?(rule, movement), do: rule.account_name
    end)
  end

  defp rule_matches?(%{conditions: conditions, match_type: :all}, movement) do
    Enum.all?(conditions, &condition_matches?(&1, movement))
  end

  defp rule_matches?(%{conditions: conditions, match_type: :any}, movement) do
    Enum.any?(conditions, &condition_matches?(&1, movement))
  end

  defp condition_matches?(%{field: :description, comparator: :contains, value: value}, movement) do
    String.contains?(movement.description || "", value)
  end

  defp condition_matches?(%{field: :description, comparator: :equals, value: value}, movement) do
    movement.description == value
  end

  defp condition_matches?(%{field: :description, comparator: :regex, value: value}, movement) do
    case Regex.compile(value) do
      {:ok, regex} -> Regex.match?(regex, movement.description || "")
      {:error, _} -> false
    end
  end

  defp condition_matches?(%{field: :amount, comparator: :equals, value: value}, movement) do
    movement.amount == parse_integer(value)
  end

  defp condition_matches?(%{field: :amount, comparator: :greater_than, value: value}, movement) do
    movement.amount > parse_integer(value)
  end

  defp condition_matches?(%{field: :amount, comparator: :less_than, value: value}, movement) do
    movement.amount < parse_integer(value)
  end

  defp condition_matches?(%{field: :on_date, comparator: :equals, value: value}, movement) do
    movement.on_date == parse_date(value)
  end

  defp condition_matches?(%{field: :on_date, comparator: :between, value: from, value_to: to}, movement) do
    from = parse_date(from)
    to = parse_date(to)
    not is_nil(from) and not is_nil(to) and Date.compare(movement.on_date, from) != :lt and
      Date.compare(movement.on_date, to) != :gt
  end

  defp condition_matches?(_condition, _movement), do: false

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp parse_date(value) when is_struct(value, Date), do: value

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp parse_date(_value), do: nil
```

Y añadir la cláusula `apply/2` correspondiente:

```elixir
  def apply(%__MODULE__{movements: movements} = reconciliation, %MovementsImported{movements: imported}) do
    new_movements =
      Map.new(imported, fn movement ->
        {movement.id, Map.from_struct(movement)}
      end)

    %__MODULE__{reconciliation | movements: Map.merge(movements, new_movements)}
  end
```

**Nota de orden:** esta nueva cláusula `apply/2` para `MovementsImported`, igual que las de `execute/2` para `ImportMovements`, debe colocarse antes del catch-all `def apply(reconciliation, _event), do: reconciliation` que ya existe al final del módulo — Elixir resuelve `def` con pattern matching en orden de aparición.

- [x] **Step 4: Ejecutar y comprobar que pasa**

Run: `cd apps/conta && mix test test/aggregate/reconciliation_test.exs`
Expected: PASS (12 tests)

- [x] **Step 5: Commit**

```bash
git add apps/conta/lib/conta/aggregate/reconciliation.ex apps/conta/test/aggregate/reconciliation_test.exs
git commit -m "feat: evaluate match rules when importing movements"
```

## Task 8: `UpdateMovement` con reevaluación condicional

**Files:**
- Modify: `apps/conta/lib/conta/aggregate/reconciliation.ex`
- Modify: `apps/conta/test/aggregate/reconciliation_test.exs`

- [x] **Step 1: Añadir los tests que fallan**

```elixir
  alias Conta.Command.UpdateMovement
  alias Conta.Event.MovementUpdated

  describe "update movement" do
    setup do
      rule = %{
        id: Ecto.UUID.generate(),
        name: "Netflix",
        conditions: [%{field: :description, comparator: :contains, value: "NETFLIX", value_to: nil}],
        match_type: :all,
        account_name: ["Expenses", "Subscriptions"]
      }

      movement = %{
        id: Ecto.UUID.generate(),
        on_date: ~D[2026-07-01],
        description: "unrelated typo",
        amount: -1399,
        currency: :EUR,
        asset_account_name: ["Assets", "Bank"],
        account_name: nil,
        source: "bank x",
        transacted: false
      }

      %{reconciliation: %Reconciliation{match_rules: [rule], movements: %{movement.id => movement}}, movement: movement}
    end

    test "editing description re-evaluates rules when account_name is nil", %{reconciliation: reconciliation, movement: movement} do
      command = %UpdateMovement{id: movement.id, changes: %{"description" => "NETFLIX.COM"}}

      event = Reconciliation.execute(reconciliation, command)
      assert %MovementUpdated{id: id, description: "NETFLIX.COM", account_name: ["Expenses", "Subscriptions"]} = event
      assert id == movement.id

      reconciliation = Reconciliation.apply(reconciliation, event)
      assert reconciliation.movements[movement.id].account_name == ["Expenses", "Subscriptions"]
    end

    test "editing description does not overwrite a manually-assigned account_name", %{reconciliation: reconciliation, movement: movement} do
      movement_with_account = %{movement | account_name: ["Expenses", "Groceries"]}
      reconciliation = %Reconciliation{reconciliation | movements: %{movement.id => movement_with_account}}

      command = %UpdateMovement{id: movement.id, changes: %{"description" => "NETFLIX.COM typo fix"}}

      event = Reconciliation.execute(reconciliation, command)
      assert %MovementUpdated{account_name: nil} = event

      reconciliation = Reconciliation.apply(reconciliation, event)
      assert reconciliation.movements[movement.id].account_name == ["Expenses", "Groceries"]
      assert reconciliation.movements[movement.id].description == "NETFLIX.COM typo fix"
    end

    test "editing account_name directly is respected as-is and skips re-evaluation", %{reconciliation: reconciliation, movement: movement} do
      command = %UpdateMovement{id: movement.id, changes: %{"account_name" => ["Expenses", "Manual"]}}

      event = Reconciliation.execute(reconciliation, command)
      assert %MovementUpdated{account_name: ["Expenses", "Manual"]} = event

      reconciliation = Reconciliation.apply(reconciliation, event)
      assert reconciliation.movements[movement.id].account_name == ["Expenses", "Manual"]
    end

    test "updating an unknown movement returns an error", %{reconciliation: reconciliation} do
      assert {:error, %{id: ["not found"]}} =
               Reconciliation.execute(reconciliation, %UpdateMovement{id: Ecto.UUID.generate(), changes: %{}})
    end
  end
```

- [x] **Step 2: Ejecutar y comprobar que falla**

Run: `cd apps/conta && mix test test/aggregate/reconciliation_test.exs`
Expected: FAIL — no hay cláusula `execute/2` para `UpdateMovement`.

- [x] **Step 3: Implementar**

`MovementUpdated.changeset/2` (Task 5) already ends its own pipeline with `|> get_result()` — same reason as in Task 7, do **not** pipe its result into `Conta.EctoHelpers.get_result/1` again, that would raise on the happy path.

`changes` arrives as a free-form map of mostly-string values (the LiveView in Task 30 builds it straight from form params), but `evaluate_rules/2` (Task 7) compares against already-typed `movement` fields (`on_date` is a `Date`, `amount` is an `integer`) — so raw strings must be cast to the same types **before** being merged into `updated` and handed to `evaluate_rules/2`, reusing the `parse_integer/1` and `parse_date/1` helpers already defined in Task 7 for the same purpose:

```elixir
  alias Conta.Command.UpdateMovement
  alias Conta.Event.MovementUpdated

  def execute(%__MODULE__{movements: movements, match_rules: match_rules}, %UpdateMovement{id: id, changes: changes}) do
    case movements[id] do
      nil ->
        {:error, %{id: ["not found"]}}

      movement ->
        updated = apply_changes_to_movement(movement, changes)

        account_name =
          cond do
            Map.has_key?(changes, "account_name") -> updated.account_name
            not is_nil(movement.account_name) -> movement.account_name
            :else -> evaluate_rules(match_rules, updated)
          end

        %{
          id: id,
          on_date: updated.on_date,
          description: updated.description,
          amount: updated.amount,
          currency: updated.currency,
          account_name: account_name
        }
        |> MovementUpdated.changeset()
    end
  end

  defp apply_changes_to_movement(movement, changes) do
    movement
    |> maybe_put(:on_date, changes["on_date"], &parse_date/1)
    |> maybe_put(:description, changes["description"], & &1)
    |> maybe_put(:amount, changes["amount"], &parse_integer/1)
    |> maybe_put(:currency, changes["currency"], &parse_currency/1)
    |> maybe_put(:account_name, changes["account_name"], & &1)
  end

  defp maybe_put(map, _key, nil, _cast_fun), do: map
  defp maybe_put(map, key, value, cast_fun), do: Map.put(map, key, cast_fun.(value))

  defp parse_currency(value) when is_atom(value), do: value

  defp parse_currency(value) when is_binary(value) do
    currencies = Money.Currency.all() |> Map.keys() |> Enum.map(&to_string/1)
    if value in currencies, do: String.to_atom(value)
  end
```

`parse_currency/1` mirrors the existing cast pattern in `apps/conta/lib/conta/automator.ex` (`cast/3` clause for `%Param{type: :currency}`) — `String.to_atom/1` here only ever converts a string already validated against `Money.Currency.all()`'s keys, so it can't create unbounded new atoms.

Y la cláusula `apply/2`:

```elixir
  def apply(%__MODULE__{movements: movements} = reconciliation, %MovementUpdated{} = event) do
    movements =
      Map.update!(movements, event.id, fn movement ->
        movement
        |> Map.put(:on_date, event.on_date)
        |> Map.put(:description, event.description)
        |> Map.put(:amount, event.amount)
        |> Map.put(:currency, event.currency)
        |> Map.put(:account_name, event.account_name)
      end)

    %__MODULE__{reconciliation | movements: movements}
  end
```

**Nota:** `MovementUpdated.changeset/2` (Task 5) solo tiene `id` como `required`; el resto de campos deben admitir venir vacíos porque `UpdateMovement` es una edición parcial — revisar que ese changeset no falle cuando, p. ej., solo cambia `account_name` y el resto de campos vienen de `movement` (siempre presentes, nunca `nil`, así que no hay problema real, pero confirmarlo al correr el test).

- [x] **Step 4: Ejecutar y comprobar que pasa**

Run: `cd apps/conta && mix test test/aggregate/reconciliation_test.exs`
Expected: PASS (16 tests)

- [x] **Step 5: Commit**

```bash
git add apps/conta/lib/conta/aggregate/reconciliation.ex apps/conta/test/aggregate/reconciliation_test.exs
git commit -m "feat: update movement with conditional rule re-evaluation"
```

## Task 9: `RemoveMovement` y `MarkMovementTransacted`

**Files:**
- Modify: `apps/conta/lib/conta/aggregate/reconciliation.ex`
- Modify: `apps/conta/test/aggregate/reconciliation_test.exs`

- [x] **Step 1: Añadir los tests que fallan**

```elixir
  alias Conta.Command.MarkMovementTransacted
  alias Conta.Command.RemoveMovement
  alias Conta.Event.MovementRemoved
  alias Conta.Event.MovementTransacted

  describe "remove and mark movement" do
    setup do
      movement = %{
        id: Ecto.UUID.generate(),
        on_date: ~D[2026-07-01],
        description: "x",
        amount: -100,
        currency: :EUR,
        asset_account_name: ["Assets", "Bank"],
        account_name: ["Expenses", "Misc"],
        source: "bank x",
        transacted: false
      }

      %{reconciliation: %Reconciliation{movements: %{movement.id => movement}}, movement: movement}
    end

    test "remove an existing movement", %{reconciliation: reconciliation, movement: movement} do
      event = Reconciliation.execute(reconciliation, %RemoveMovement{id: movement.id})
      assert %MovementRemoved{id: id} = event
      assert id == movement.id

      reconciliation = Reconciliation.apply(reconciliation, event)
      assert reconciliation.movements == %{}
    end

    test "removing an unknown movement returns an error", %{reconciliation: reconciliation} do
      assert {:error, %{id: ["not found"]}} = Reconciliation.execute(reconciliation, %RemoveMovement{id: Ecto.UUID.generate()})
    end

    test "mark a movement as transacted", %{reconciliation: reconciliation, movement: movement} do
      event = Reconciliation.execute(reconciliation, %MarkMovementTransacted{id: movement.id})
      assert %MovementTransacted{id: id} = event
      assert id == movement.id

      reconciliation = Reconciliation.apply(reconciliation, event)
      assert reconciliation.movements[movement.id].transacted
    end

    test "marking an unknown movement as transacted returns an error", %{reconciliation: reconciliation} do
      assert {:error, %{id: ["not found"]}} =
               Reconciliation.execute(reconciliation, %MarkMovementTransacted{id: Ecto.UUID.generate()})
    end
  end
```

- [x] **Step 2: Ejecutar y comprobar que falla**

Run: `cd apps/conta && mix test test/aggregate/reconciliation_test.exs`
Expected: FAIL

- [x] **Step 3: Implementar**

Igual que en las Tasks 7 y 8: `MovementRemoved.changeset/2` y `MovementTransacted.changeset/2` ya terminan en `get_result()`, así que no se vuelve a envolver el resultado.

```elixir
  alias Conta.Command.MarkMovementTransacted
  alias Conta.Command.RemoveMovement
  alias Conta.Event.MovementRemoved
  alias Conta.Event.MovementTransacted

  def execute(%__MODULE__{movements: movements}, %RemoveMovement{id: id} = command) do
    if Map.has_key?(movements, id) do
      command
      |> Map.from_struct()
      |> MovementRemoved.changeset()
    else
      {:error, %{id: ["not found"]}}
    end
  end

  def execute(%__MODULE__{movements: movements}, %MarkMovementTransacted{id: id} = command) do
    if Map.has_key?(movements, id) do
      command
      |> Map.from_struct()
      |> MovementTransacted.changeset()
    else
      {:error, %{id: ["not found"]}}
    end
  end
```

```elixir
  def apply(%__MODULE__{movements: movements} = reconciliation, %MovementRemoved{id: id}) do
    %__MODULE__{reconciliation | movements: Map.delete(movements, id)}
  end

  def apply(%__MODULE__{movements: movements} = reconciliation, %MovementTransacted{id: id}) do
    %__MODULE__{reconciliation | movements: Map.update!(movements, id, &Map.put(&1, :transacted, true))}
  end
```

- [x] **Step 4: Ejecutar y comprobar que pasa**

Run: `cd apps/conta && mix test test/aggregate/reconciliation_test.exs`
Expected: PASS (20 tests)

- [x] **Step 5: Commit**

```bash
git add apps/conta/lib/conta/aggregate/reconciliation.ex apps/conta/test/aggregate/reconciliation_test.exs
git commit -m "feat: remove and mark-transacted movement commands"
```

## Task 10: Registrar el aggregate en el router de Commanded

**Files:**
- Modify: `apps/conta/lib/conta/commanded/router.ex`

- [x] **Step 1: Añadir los `alias` y las líneas `identify`/`dispatch`**

```elixir
  alias Conta.Aggregate.Reconciliation

  alias Conta.Command.ImportMovements
  alias Conta.Command.MarkMovementTransacted
  alias Conta.Command.RemoveMatchRule
  alias Conta.Command.RemoveMovement
  alias Conta.Command.ReorderMatchRules
  alias Conta.Command.SetMatchRule
  alias Conta.Command.UpdateMovement
```

```elixir
  identify(Reconciliation, by: :reconciliation)

  dispatch(ImportMovements, to: Reconciliation)
  dispatch(MarkMovementTransacted, to: Reconciliation)
  dispatch(RemoveMatchRule, to: Reconciliation)
  dispatch(RemoveMovement, to: Reconciliation)
  dispatch(ReorderMatchRules, to: Reconciliation)
  dispatch(SetMatchRule, to: Reconciliation)
  dispatch(UpdateMovement, to: Reconciliation)
```

Mantener el orden alfabético de los `alias`, como en el resto del fichero.

- [x] **Step 2: Comprobar que compila**

Run: `cd apps/conta && mix compile --warnings-as-errors`
Expected: compila sin warnings.

- [x] **Step 3: Commit**

```bash
git add apps/conta/lib/conta/commanded/router.ex
git commit -m "feat: register Reconciliation aggregate in the Commanded router"
```

## Task 11: Migración de las tablas de lectura

**Files:**
- Create: `apps/conta/priv/repo/migrations/<timestamp>_create_reconciliation_tables.exs`

- [x] **Step 1: Generar la migración**

Run: `cd apps/conta && mix ecto.gen.migration create_reconciliation_tables`

- [x] **Step 2: Escribir el contenido**

```elixir
defmodule Conta.Repo.Migrations.CreateReconciliationTables do
  use Ecto.Migration

  def change do
    create table(:reconciliation_match_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :conditions, :jsonb
      add :match_type, :string
      add :account_name, {:array, :string}
      add :position, :integer
    end

    create index(:reconciliation_match_rules, [:position])

    create table(:reconciliation_movements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :on_date, :date
      add :description, :string
      add :amount, :integer
      add :currency, :string
      add :asset_account_name, {:array, :string}
      add :account_name, {:array, :string}
      add :source, :string
      add :transacted, :boolean, default: false
    end

    create index(:reconciliation_movements, [:asset_account_name])
  end
end
```

- [x] **Step 3: Ejecutar la migración**

Run: `cd apps/conta && mix ecto.migrate`
Expected: `Migrated <timestamp> ... create_reconciliation_tables.exs`

- [x] **Step 4: Commit**

```bash
git add apps/conta/priv/repo/migrations/
git commit -m "feat: create reconciliation read-model tables"
```

## Task 12: Read-model schemas del projector

**Files:**
- Create: `apps/conta/lib/conta/projector/reconciliation/match_rule.ex`
- Create: `apps/conta/lib/conta/projector/reconciliation/movement.ex`

- [x] **Step 1: Implementar `Conta.Projector.Reconciliation.MatchRule`**

```elixir
defmodule Conta.Projector.Reconciliation.MatchRule do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder, only: ~w[id name conditions match_type account_name position]a}
  typed_schema "reconciliation_match_rules" do
    field :name, :string

    embeds_many :conditions, Condition, primary_key: false, on_replace: :delete do
      field :field, Ecto.Enum, values: ~w[description amount on_date]a
      field :comparator, Ecto.Enum, values: ~w[contains equals regex greater_than less_than between]a
      field :value, :string
      field :value_to, :string
    end

    field :match_type, Ecto.Enum, values: ~w[all any]a, default: :all
    field :account_name, {:array, :string}
    field :position, :integer
  end

  @required_fields ~w[id name match_type account_name position]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields)
    |> cast_embed(:conditions, with: &changeset_condition/2)
    |> validate_required(@required_fields)
  end

  @doc false
  def changeset_condition(model, params) do
    cast(model, params, ~w[field comparator value value_to]a)
  end
end

defimpl Jason.Encoder, for: Conta.Projector.Reconciliation.MatchRule.Condition do
  def encode(condition, _opts) do
    Jason.encode!(Map.from_struct(condition))
  end
end
```

`MatchRule` deriva `Jason.Encoder` incluyendo `:conditions` (línea con `@derive`), así que su embed inline `Condition` necesita esta implementación — mismo motivo y mismo patrón que `Conta.Event.MatchRuleSet.Condition` en la Task 3, y que el `Conta.Projector.Automator.Param`/`Conta.Event.ShortcutSet.Param` ya existentes en el codebase. Sin esto, `Jason.encode!/1` sobre un `%MatchRule{}` fallaría con `Protocol.UndefinedError`.

**Notas importantes (encontradas durante la implementación, ya corregidas arriba):**
- `cast_embed(:conditions)` **necesita** `with: &changeset_condition/2` — sin una función de changeset propia para el embed inline `Condition`, `cast_embed/3` intenta invocar `Condition.changeset/2` por defecto y falla con `UndefinedFunctionError` en cuanto la lista de condiciones no esté vacía (que es el caso normal). `changeset_condition/2` es deliberadamente ligero (solo `cast/3`, sin `validate_required`) porque los datos ya vinieron validados del comando/aggregate — no hace falta revalidar aquí.
- `:id` **debe** estar en `@required_fields` de `MatchRule` (y de `Movement`, más abajo) — de lo contrario, un `id` pasado dentro del mapa de `params` (en vez de preestablecido en el struct inicial, como sí hace el propio projector con `%MatchRule{id: event.id}`) se descartaría silenciosamente y el `INSERT` fallaría contra la columna `NOT NULL` de la clave primaria. Añadirlo a `@required_fields` no rompe la otra forma de llamada (struct con id preestablecido) — `validate_required/2` cae de vuelta al dato ya presente en el struct cuando el campo no viene en `params`.
- `embeds_many :conditions, Condition, primary_key: false, ...` — sin `primary_key: false`, el embed inline recibe por defecto un `:id` autogenerado que no existe en el evento origen (`Conta.Event.MatchRuleSet.Condition`, que sí declara `primary_key: false`), colando una clave `"id": null` espuria en el JSON persistido.

- [x] **Step 2: Implementar `Conta.Projector.Reconciliation.Movement`**

```elixir
defmodule Conta.Projector.Reconciliation.Movement do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder, only: ~w[id on_date description amount currency asset_account_name account_name source transacted]a}
  typed_schema "reconciliation_movements" do
    field :on_date, :date
    field :description, :string
    field :amount, :integer
    field :currency, Money.Ecto.Currency.Type
    field :asset_account_name, {:array, :string}
    field :account_name, {:array, :string}
    field :source, :string
    field :transacted, :boolean, default: false
  end

  @required_fields ~w[id on_date description amount currency asset_account_name transacted]a
  @optional_fields ~w[account_name source]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
```

- [x] **Step 3: Comprobar que compila**

Run: `cd apps/conta && mix compile --warnings-as-errors`

- [x] **Step 4: Commit**

```bash
git add apps/conta/lib/conta/projector/reconciliation/
git commit -m "feat: add Reconciliation read-model schemas"
```

## Task 13: Projector `Conta.Projector.Reconciliation`

**Files:**
- Create: `apps/conta/lib/conta/projector/reconciliation.ex`
- Test: `apps/conta/test/projector/reconciliation_test.exs`

- [x] **Step 1: Escribir los tests que fallan**

```elixir
defmodule Conta.Projector.ReconciliationTest do
  use Conta.DataCase
  alias Conta.Projector.Reconciliation

  setup do
    version =
      if pv = Repo.get(Reconciliation.ProjectionVersion, "Conta.Projector.Reconciliation") do
        pv.last_seen_version + 1
      else
        1
      end

    on_exit(fn ->
      Repo.delete_all(Reconciliation.MatchRule)
      Repo.delete_all(Reconciliation.Movement)
      Repo.delete_all(Reconciliation.ProjectionVersion)
    end)

    %{handler_name: "Conta.Projector.Reconciliation", event_number: version}
  end

  describe "match rules" do
    test "MatchRuleSet inserts a row at the next position", metadata do
      event = %Conta.Event.MatchRuleSet{
        id: Ecto.UUID.generate(),
        name: "Netflix",
        conditions: [%Conta.Event.MatchRuleSet.Condition{field: :description, comparator: :contains, value: "NETFLIX"}],
        match_type: :all,
        account_name: ["Expenses", "Subscriptions"]
      }

      assert :ok = Reconciliation.handle(event, metadata)

      assert %Reconciliation.MatchRule{name: "Netflix", position: 0} =
               Repo.get_by!(Reconciliation.MatchRule, id: event.id)
    end

    test "MatchRuleRemoved deletes the row", metadata do
      rule = insert_match_rule(position: 0)

      event = %Conta.Event.MatchRuleRemoved{id: rule.id}
      assert :ok = Reconciliation.handle(event, metadata)

      refute Repo.get(Reconciliation.MatchRule, rule.id)
    end

    test "MatchRulesReordered updates positions", metadata do
      rule_a = insert_match_rule(position: 0)
      rule_b = insert_match_rule(position: 1)

      event = %Conta.Event.MatchRulesReordered{ids: [rule_b.id, rule_a.id]}
      assert :ok = Reconciliation.handle(event, metadata)

      assert Repo.get!(Reconciliation.MatchRule, rule_b.id).position == 0
      assert Repo.get!(Reconciliation.MatchRule, rule_a.id).position == 1
    end
  end

  describe "movements" do
    test "MovementsImported inserts one row per movement", metadata do
      event = %Conta.Event.MovementsImported{
        movements: [
          %Conta.Event.MovementsImported.Movement{
            id: Ecto.UUID.generate(),
            on_date: ~D[2026-07-01],
            description: "x",
            amount: -100,
            currency: :EUR,
            asset_account_name: ["Assets", "Bank"],
            account_name: nil,
            transacted: false
          }
        ]
      }

      assert :ok = Reconciliation.handle(event, metadata)
      assert [%Reconciliation.Movement{description: "x"}] = Repo.all(Reconciliation.Movement)
    end

    test "MovementUpdated updates the row", metadata do
      movement = insert_movement()

      event = %Conta.Event.MovementUpdated{
        id: movement.id,
        on_date: movement.on_date,
        description: "new description",
        amount: movement.amount,
        currency: movement.currency,
        account_name: ["Expenses", "Manual"]
      }

      assert :ok = Reconciliation.handle(event, metadata)

      updated = Repo.get!(Reconciliation.Movement, movement.id)
      assert updated.description == "new description"
      assert updated.account_name == ["Expenses", "Manual"]
    end

    test "MovementUpdated with account_name: nil preserves the existing account_name", metadata do
      movement = insert_movement(account_name: ["Expenses", "Groceries"])

      event = %Conta.Event.MovementUpdated{
        id: movement.id,
        on_date: movement.on_date,
        description: "new description",
        amount: movement.amount,
        currency: movement.currency,
        account_name: nil
      }

      assert :ok = Reconciliation.handle(event, metadata)

      updated = Repo.get!(Reconciliation.Movement, movement.id)
      assert updated.description == "new description"
      assert updated.account_name == ["Expenses", "Groceries"]
    end

    test "MovementRemoved deletes the row", metadata do
      movement = insert_movement()

      assert :ok = Reconciliation.handle(%Conta.Event.MovementRemoved{id: movement.id}, metadata)
      refute Repo.get(Reconciliation.Movement, movement.id)
    end

    test "MovementTransacted sets transacted to true", metadata do
      movement = insert_movement()

      assert :ok = Reconciliation.handle(%Conta.Event.MovementTransacted{id: movement.id}, metadata)
      assert Repo.get!(Reconciliation.Movement, movement.id).transacted
    end
  end

  defp insert_match_rule(attrs) do
    %Reconciliation.MatchRule{}
    |> Reconciliation.MatchRule.changeset(
      Map.merge(
        %{id: Ecto.UUID.generate(), name: "rule", conditions: [], match_type: :all, account_name: ["X"]},
        Map.new(attrs)
      )
    )
    |> Repo.insert!()
  end

  defp insert_movement(attrs \\ %{}) do
    %Reconciliation.Movement{}
    |> Reconciliation.Movement.changeset(
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          on_date: ~D[2026-07-01],
          description: "x",
          amount: -100,
          currency: "EUR",
          asset_account_name: ["Assets", "Bank"],
          transacted: false
        },
        Map.new(attrs)
      )
    )
    |> Repo.insert!()
  end
end
```

**Nota:** `:id` debe estar incluido en `@required_fields` de ambos schemas del projector (Task 12) — sin eso, ni estas fixtures ni ningún llamador que pase `id` dentro del mapa de params (en vez de preestablecerlo en el struct, como sí hace el propio projector más abajo con `%MatchRule{id: event.id}`/`%Movement{id: movement.id}`) conseguirían persistir un id real, y `Repo.insert!` fallaría contra la columna `NOT NULL` de la clave primaria.

- [x] **Step 2: Ejecutar y comprobar que falla**

Run: `cd apps/conta && mix test test/projector/reconciliation_test.exs`
Expected: FAIL — `Conta.Projector.Reconciliation` no existe.

- [x] **Step 3: Implementar el projector**

```elixir
defmodule Conta.Projector.Reconciliation do
  use Conta.Projector,
    application: Conta.Commanded.Application,
    repo: Conta.Repo,
    name: __MODULE__,
    consistency: Application.compile_env(:conta, :consistency, :eventual)

  import Ecto.Query, only: [from: 2]

  alias Conta.Event.MatchRuleRemoved
  alias Conta.Event.MatchRuleSet
  alias Conta.Event.MatchRulesReordered
  alias Conta.Event.MovementRemoved
  alias Conta.Event.MovementTransacted
  alias Conta.Event.MovementUpdated
  alias Conta.Event.MovementsImported

  alias Conta.Projector.Reconciliation.MatchRule
  alias Conta.Projector.Reconciliation.Movement

  alias Conta.Repo

  project(%MatchRuleSet{} = event, _metadata, fn multi ->
    conditions = Enum.map(event.conditions, &Map.from_struct/1)

    if rule = Repo.get(MatchRule, event.id) do
      changeset = MatchRule.changeset(rule, %{name: event.name, conditions: conditions, match_type: event.match_type, account_name: event.account_name})
      Ecto.Multi.update(multi, :match_rule_update, changeset)
    else
      next_position = (Repo.aggregate(MatchRule, :max, :position) || -1) + 1

      changeset =
        %MatchRule{id: event.id}
        |> MatchRule.changeset(%{
          name: event.name,
          conditions: conditions,
          match_type: event.match_type,
          account_name: event.account_name,
          position: next_position
        })

      Ecto.Multi.insert(multi, :match_rule_create, changeset)
    end
  end)

  project(%MatchRuleRemoved{} = event, _metadata, fn multi ->
    if rule = Repo.get(MatchRule, event.id) do
      Ecto.Multi.delete(multi, :match_rule_delete, rule)
    else
      multi
    end
  end)

  project(%MatchRulesReordered{} = event, _metadata, fn multi ->
    event.ids
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {id, position}, multi ->
      Ecto.Multi.update_all(
        multi,
        {:reorder, id},
        from(r in MatchRule, where: r.id == ^id),
        set: [position: position]
      )
    end)
  end)

  project(%MovementsImported{} = event, _metadata, fn multi ->
    Enum.reduce(event.movements, multi, fn movement, multi ->
      changeset = %Movement{id: movement.id} |> Movement.changeset(Map.from_struct(movement))
      Ecto.Multi.insert(multi, {:movement_create, movement.id}, changeset)
    end)
  end)

  project(%MovementUpdated{} = event, _metadata, fn multi ->
    if movement = Repo.get(Movement, event.id) do
      changeset =
        Movement.changeset(movement, %{
          on_date: event.on_date,
          description: event.description,
          amount: event.amount,
          currency: event.currency,
          account_name: event.account_name || movement.account_name
        })

      Ecto.Multi.update(multi, :movement_update, changeset)
    else
      multi
    end
  end)

  project(%MovementRemoved{} = event, _metadata, fn multi ->
    if movement = Repo.get(Movement, event.id) do
      Ecto.Multi.delete(multi, :movement_delete, movement)
    else
      multi
    end
  end)

  project(%MovementTransacted{} = event, _metadata, fn multi ->
    if movement = Repo.get(Movement, event.id) do
      Ecto.Multi.update(multi, :movement_transacted, Movement.changeset(movement, %{transacted: true}))
    else
      multi
    end
  end)
end
```

**Nota sobre `account_name: nil` en `MovementUpdated`:** durante la implementación de la Task 8, el aggregate cambió la semántica de este campo — `account_name: nil` en el evento ya **no** significa "sin cuenta" sino "sin cambios, preservar lo que ya tenga el movimiento" (necesario para que editar `description` u otro campo no borre una cuenta ya asignada manualmente o por match previo; ver el `apply/2` del aggregate para `MovementUpdated`, que hace exactamente `event.account_name || movement.account_name`). El projector **debe replicar la misma lógica de fusión** — de ahí el `event.account_name || movement.account_name` en el `changeset` de arriba — en vez de sobrescribir ciegamente con `event.account_name`, o se perdería una cuenta ya asignada cada vez que se edite un campo no relacionado. No "simplificar" esto a un sobrescrito directo.

- [x] **Step 4: Ejecutar y comprobar que pasa**

Run: `cd apps/conta && mix test test/projector/reconciliation_test.exs`
Expected: PASS (8 tests)

- [x] **Step 4.5: Registrar el projector en el árbol de supervisión**

**Este paso faltaba en la versión original del plan** — sin él, el projector nunca se suscribe al stream de eventos en la app real (dev/prod); solo funcionaría en los tests, que invocan `handle/2` directamente. Añadir `Conta.Projector.Reconciliation` a la lista `children` de `apps/conta/lib/conta/application.ex`, en orden alfabético junto a los demás projectors:

```elixir
      Conta.Projector.Automator,
      Conta.Projector.Book,
      Conta.Projector.Directory,
      Conta.Projector.Ledger,
      Conta.Projector.Reconciliation,
      Conta.Projector.Stats
```

Añadir también un test de la rama de actualización de `MatchRuleSet` que faltaba (el test existente solo cubre la creación): reenviar `MatchRuleSet` con el `id` de una regla ya insertada y comprobar que se actualiza en el sitio (posición intacta, condiciones reemplazadas), en vez de crear una fila nueva.

- [x] **Step 5: Commit**

```bash
git add apps/conta/lib/conta/projector/reconciliation.ex apps/conta/test/projector/reconciliation_test.exs apps/conta/lib/conta/application.ex
git commit -m "feat: add Reconciliation projector"
```

---

# FASE 2 — Orquestación de confirmación

## Task 14: Contexto `Conta.Reconciliation` — listados y helpers de comando

**Files:**
- Create: `apps/conta/lib/conta/reconciliation.ex`
- Test: `apps/conta/test/conta/reconciliation_context_test.exs`
- Create: `apps/conta/test/support/fixtures/reconciliation_fixtures.ex`

- [x] **Step 1: Crear las fixtures (siguiendo el patrón de `automator_fixtures.ex`)**

Antes de escribir esto, leer `apps/conta/test/support/fixtures/automator_fixtures.ex` para replicar exactamente el estilo de `ExMachina` (o el helper que use ese fichero) usado en el proyecto.

```elixir
defmodule Conta.ReconciliationFixtures do
  use ExMachina.Ecto, repo: Conta.Repo

  alias Conta.Projector.Reconciliation.MatchRule
  alias Conta.Projector.Reconciliation.Movement

  def match_rule_factory do
    %MatchRule{
      id: Ecto.UUID.generate(),
      name: sequence(:name, &"rule #{&1}"),
      conditions: [%MatchRule.Condition{field: :description, comparator: :contains, value: "X"}],
      match_type: :all,
      account_name: ["Expenses", "Misc"],
      position: sequence(:position, & &1)
    }
  end

  def movement_factory do
    %Movement{
      id: Ecto.UUID.generate(),
      on_date: ~D[2026-07-01],
      description: sequence(:description, &"movement #{&1}"),
      amount: -1000,
      currency: :EUR,
      asset_account_name: ["Assets", "Bank"],
      account_name: nil,
      source: "test importer",
      transacted: false
    }
  end
end
```

Ajustar la sintaxis exacta de `sequence/2` y `use ExMachina.Ecto` al patrón real visto en `automator_fixtures.ex` — no asumir, verificar contra el fichero real antes de escribir esto.

- [x] **Step 2: Escribir los tests que fallan**

```elixir
defmodule Conta.ReconciliationContextTest do
  use Conta.DataCase
  import Conta.ReconciliationFixtures

  alias Conta.Reconciliation
  alias Conta.Projector.Reconciliation.MatchRule
  alias Conta.Projector.Reconciliation.Movement

  describe "match rules" do
    test "list_match_rules/0 returns rules ordered by position" do
      rule_b = insert(:match_rule, position: 1)
      rule_a = insert(:match_rule, position: 0)

      assert [%MatchRule{id: id_a}, %MatchRule{id: id_b}] = Reconciliation.list_match_rules()
      assert id_a == rule_a.id
      assert id_b == rule_b.id
    end

    test "get_match_rule!/1 returns the rule" do
      rule = insert(:match_rule)
      assert %MatchRule{id: id} = Reconciliation.get_match_rule!(rule.id)
      assert id == rule.id
    end
  end

  describe "movements" do
    test "list_movements/0 returns all pending movements" do
      movement = insert(:movement)
      result = Reconciliation.list_movements()
      assert Enum.any?(result, &(&1.id == movement.id))
    end

    test "list_movements/0 returns movements regardless of account_name" do
      with_account = insert(:movement, account_name: ["Expenses", "Misc"])
      without_account = insert(:movement, account_name: nil)

      result = Reconciliation.list_movements()
      assert Enum.find(result, &(&1.id == with_account.id))
      assert Enum.find(result, &(&1.id == without_account.id))
    end

    test "get_movement!/1 returns the movement" do
      movement = insert(:movement)
      assert %Movement{id: id} = Reconciliation.get_movement!(movement.id)
      assert id == movement.id
    end
  end
end
```

- [x] **Step 3: Ejecutar y comprobar que falla**

Run: `cd apps/conta && mix test test/conta/reconciliation_context_test.exs`
Expected: FAIL — `Conta.Reconciliation` no existe.

- [x] **Step 4: Implementar los listados**

```elixir
defmodule Conta.Reconciliation do
  import Ecto.Query, only: [from: 2]

  alias Conta.Projector.Reconciliation.MatchRule
  alias Conta.Projector.Reconciliation.Movement
  alias Conta.Repo

  def list_match_rules do
    from(r in MatchRule, order_by: r.position)
    |> Repo.all()
  end

  def get_match_rule!(id) do
    Repo.get!(MatchRule, id)
  end

  def list_movements do
    from(m in Movement, order_by: m.on_date)
    |> Repo.all()
  end

  def get_movement!(id) do
    Repo.get!(Movement, id)
  end
end
```

- [x] **Step 5: Ejecutar y comprobar que pasa**

Run: `cd apps/conta && mix test test/conta/reconciliation_context_test.exs`
Expected: PASS

- [x] **Step 6: Commit**

```bash
git add apps/conta/lib/conta/reconciliation.ex apps/conta/test/conta/reconciliation_context_test.exs apps/conta/test/support/fixtures/reconciliation_fixtures.ex
git commit -m "feat: add Reconciliation context with list/get helpers"
```

## Task 15: `confirm_movement/1` — camino feliz y camino de error

**Files:**
- Modify: `apps/conta/lib/conta/reconciliation.ex`
- Modify: `apps/conta/test/conta/reconciliation_context_test.exs`

Esta es la pieza de mayor riesgo de todo el proyecto (evita transacciones duplicadas). Sus tests son de integración real: usan `dispatch/1` de verdad y `wait_for_event/2`, igual que `shortcut_live_test.exs` — es el único patrón existente en el codebase para probar un flujo que atraviesa el aggregate real. Antes de escribir el test, es imprescindible tener una cuenta `assets` y una cuenta contrapartida reales en el `Ledger` aggregate (no solo en el read-model), igual que hace `shortcut_live_test.exs` al despachar `Automator.get_set_shortcut/1` tras un `insert` — aquí se necesita despachar `SetAccount` para ambas cuentas antes de importar movimientos.

- [x] **Step 1: Escribir los tests que fallan**

```elixir
defmodule Conta.ReconciliationContextTest do
  use Conta.DataCase
  import Commanded.Assertions.EventAssertions
  import Conta.ReconciliationFixtures
  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Reconciliation
  alias Conta.Command.ImportMovements
  alias Conta.Command.SetAccount
  alias Conta.Event.MovementsImported
  alias Conta.Event.TransactionCreated
  alias Conta.Projector.Ledger.Entry
  alias Conta.Projector.Reconciliation.Movement

  # ... (describe "match rules" / "movements" ya existentes se mantienen)

  describe "confirm_movement/1" do
    setup do
      bank_name = ["Assets", "Bank #{System.unique_integer([:positive])}"]
      expense_name = ["Expenses", "Misc #{System.unique_integer([:positive])}"]

      :ok = dispatch(%SetAccount{name: bank_name, type: :assets, currency: :EUR, ledger: "default"})
      :ok = dispatch(%SetAccount{name: expense_name, type: :expenses, currency: :EUR, ledger: "default"})

      :ok =
        dispatch(%ImportMovements{
          movements: [
            %ImportMovements.Movement{
              on_date: ~D[2026-07-01],
              description: "test movement",
              amount: -1500,
              currency: :EUR,
              asset_account_name: bank_name
            }
          ]
        })

      assert_receive_event(Conta.Commanded.Application, MovementsImported, fn event ->
        Enum.any?(event.movements, &(&1.description == "test movement"))
      end)

      movement =
        Repo.get_by!(Movement, description: "test movement", asset_account_name: bank_name)

      %{movement: movement, bank_name: bank_name, expense_name: expense_name}
    end

    test "confirms a movement with a valid account and creates the transaction", %{movement: movement, expense_name: expense_name} do
      :ok = Reconciliation.update_movement(movement.id, %{"account_name" => expense_name})

      assert {:ok, %{movement_id: confirmed_id}} = Reconciliation.confirm_movement(movement.id)
      assert confirmed_id == movement.id

      wait_for_event(Conta.Commanded.Application, TransactionCreated)

      refute Repo.get(Movement, movement.id)
    end

    test "leaves the movement pending when the counterpart account doesn't exist", %{movement: movement} do
      :ok = Reconciliation.update_movement(movement.id, %{"account_name" => ["Expenses", "Does Not Exist #{System.unique_integer([:positive])}"]})

      assert {:error, _reason} = Reconciliation.confirm_movement(movement.id)

      assert Repo.get(Movement, movement.id)
      refute Repo.get(Movement, movement.id).transacted
    end

    test "confirming a movement without an assigned account returns an error and doesn't touch it", %{movement: movement} do
      assert {:error, :no_account_assigned} = Reconciliation.confirm_movement(movement.id)
      assert Repo.get(Movement, movement.id)
    end

    test "confirming a zero-amount movement returns an error and doesn't touch it", %{movement: movement, expense_name: expense_name} do
      :ok = Reconciliation.update_movement(movement.id, %{"account_name" => expense_name, "amount" => 0})

      assert {:error, :zero_amount} = Reconciliation.confirm_movement(movement.id)

      refute Repo.get(Movement, movement.id).transacted
    end
  end
end
```

- [x] **Step 2: Ejecutar y comprobar que falla**

Run: `cd apps/conta && mix test test/conta/reconciliation_context_test.exs`
Expected: FAIL — `confirm_movement/1` y `update_movement/2` no existen.

- [x] **Step 3: Implementar `update_movement/2` (necesario para el test) y `confirm_movement/1`**

```elixir
  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Command.MarkMovementTransacted
  alias Conta.Command.RemoveMovement
  alias Conta.Command.SetAccountTransaction
  alias Conta.Command.UpdateMovement

  def update_movement(id, changes) when is_map(changes) do
    dispatch(%UpdateMovement{id: id, changes: changes})
  end

  def confirm_movement(id) do
    movement = get_movement!(id)
    confirm_movement(movement)
  end

  # Paso 0 del algoritmo del spec: si ya está `transacted: true`, un intento anterior
  # ya creó la transacción y solo falló al retirar el movimiento — no se vuelve a
  # construir ni despachar `SetAccountTransaction` (evitaría una transacción
  # duplicada), solo se reintenta la retirada.
  defp confirm_movement(%Movement{transacted: true} = movement) do
    retire_movement(movement)
  end

  defp confirm_movement(%Movement{account_name: nil}) do
    {:error, :no_account_assigned}
  end

  defp confirm_movement(%Movement{amount: 0}) do
    {:error, :zero_amount}
  end

  defp confirm_movement(%Movement{} = movement) do
    with {:ok, changeset} <- build_transaction_changeset(movement),
         command = SetAccountTransaction.to_command(changeset),
         :ok <- dispatch(command),
         :ok <- dispatch(%MarkMovementTransacted{id: movement.id}) do
      retire_movement(movement)
    end
  end

  defp retire_movement(movement) do
    with :ok <- dispatch(%RemoveMovement{id: movement.id}) do
      {:ok, %{movement_id: movement.id}}
    end
  end

  defp build_transaction_changeset(movement) do
    {asset_entry, counterpart_entry} = entries_for_amount(movement)

    changeset =
      SetAccountTransaction.changeset(%{
        "ledger" => "default",
        "on_date" => movement.on_date,
        "entries" => [asset_entry, counterpart_entry]
      })

    if changeset.valid? do
      {:ok, changeset}
    else
      Conta.EctoHelpers.get_result(changeset)
    end
  end

  defp entries_for_amount(%Movement{amount: amount} = movement) when amount > 0 do
    {
      %{"description" => movement.description, "account_name" => movement.asset_account_name, "debit" => amount},
      %{"description" => movement.description, "account_name" => movement.account_name, "credit" => amount}
    }
  end

  defp entries_for_amount(%Movement{amount: amount} = movement) when amount < 0 do
    {
      %{"description" => movement.description, "account_name" => movement.asset_account_name, "credit" => -amount},
      %{"description" => movement.description, "account_name" => movement.account_name, "debit" => -amount}
    }
  end
```

**Puntos a verificar al implementar:**
- `SetAccountTransaction.to_command/1` no existe todavía en `Conta.Command.SetAccountTransaction` (Task 1 de la Fase 1 lo definió solo para `SetMatchRule`) — añadir `def to_command(changeset), do: apply_changes(changeset)` a `apps/conta/lib/conta/command/set_account_transaction.ex` como parte de este task (mismo patrón que `SetShortcut.to_command/1`).
- El paso 0 del algoritmo del spec ("si `transacted: true`, saltar directamente a retirar") está cubierto por la cláusula `confirm_movement(%Movement{transacted: true} = movement)`, que va **antes** que la cláusula general por orden de pattern matching — no mover de sitio. Nótese que esa cláusula llama a `retire_movement/1` directamente (solo `RemoveMovement`), **no** a la cláusula general, para no volver a despachar `MarkMovementTransacted` (sería un evento redundante, aunque inofensivo) ni mucho menos `SetAccountTransaction` de nuevo.
- `retire_movement/1` es deliberadamente el único punto que despacha `RemoveMovement` — tanto el camino feliz (tras `MarkMovementTransacted`) como el reintento (`transacted: true`) pasan por ahí, para no duplicar esa lógica.
- `build_transaction_changeset/1` devuelve `{:ok, changeset}` o el resultado de `Conta.EctoHelpers.get_result/1` sobre un changeset inválido — que ya es `{:error, errors}` (revisar `apps/conta/lib/conta/ecto_helpers.ex:39-50`); no envolver ese resultado en otro `{:error, ...}` o el `with` de `confirm_movement/1` propagaría `{:error, {:error, errors}}` en vez de `{:error, errors}`.
- `dispatch/1` en este codebase devuelve `:ok` o `{:error, reason}` (ver `automator.ex:238-244`), nunca lanza excepción — el `with` de arriba asume eso.

- [x] **Step 4: Ejecutar y comprobar que pasa**

Run: `cd apps/conta && mix test test/conta/reconciliation_context_test.exs`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git add apps/conta/lib/conta/reconciliation.ex apps/conta/lib/conta/command/set_account_transaction.ex apps/conta/test/conta/reconciliation_context_test.exs
git commit -m "feat: confirm_movement/1 orchestrates transaction creation and cleanup"
```

## Task 16: `confirm_movements/1` en bloque, independiente por fila

**Files:**
- Modify: `apps/conta/lib/conta/reconciliation.ex`
- Modify: `apps/conta/test/conta/reconciliation_context_test.exs`

- [x] **Step 1: Añadir el test que falla**

```elixir
  describe "confirm_movements/1" do
    setup do
      bank_name = ["Assets", "Bank #{System.unique_integer([:positive])}"]
      good_account = ["Expenses", "Good #{System.unique_integer([:positive])}"]

      :ok = dispatch(%SetAccount{name: bank_name, type: :assets, currency: :EUR, ledger: "default"})
      :ok = dispatch(%SetAccount{name: good_account, type: :expenses, currency: :EUR, ledger: "default"})

      :ok =
        dispatch(%ImportMovements{
          movements: [
            %ImportMovements.Movement{on_date: ~D[2026-07-01], description: "ok one", amount: -100, currency: :EUR, asset_account_name: bank_name},
            %ImportMovements.Movement{on_date: ~D[2026-07-01], description: "bad one", amount: -100, currency: :EUR, asset_account_name: bank_name}
          ]
        })

      assert_receive_event(Conta.Commanded.Application, MovementsImported, fn event ->
        Enum.any?(event.movements, &(&1.description == "bad one"))
      end)

      good = Repo.get_by!(Movement, description: "ok one")
      bad = Repo.get_by!(Movement, description: "bad one")

      :ok = Reconciliation.update_movement(good.id, %{"account_name" => good_account})
      :ok = Reconciliation.update_movement(bad.id, %{"account_name" => ["Expenses", "Nonexistent #{System.unique_integer([:positive])}"]})

      %{good: good, bad: bad}
    end

    test "processes each movement independently and reports per-movement result", %{good: good, bad: bad} do
      results = Reconciliation.confirm_movements([good.id, bad.id])

      assert {:ok, %{movement_id: _}} = results[good.id]
      assert {:error, _reason} = results[bad.id]

      refute Repo.get(Movement, good.id)
      assert Repo.get(Movement, bad.id)
    end
  end
```

- [x] **Step 2: Ejecutar y comprobar que falla**

Run: `cd apps/conta && mix test test/conta/reconciliation_context_test.exs`
Expected: FAIL — `confirm_movements/1` no existe.

- [x] **Step 3: Implementar**

```elixir
  def confirm_movements(ids) when is_list(ids) do
    Map.new(ids, fn id -> {id, confirm_movement(id)} end)
  end
```

- [x] **Step 4: Ejecutar y comprobar que pasa**

Run: `cd apps/conta && mix test test/conta/reconciliation_context_test.exs`
Expected: PASS — toda la suite de Fase 1 + Fase 2.

- [x] **Step 5: Ejecutar toda la suite de `apps/conta` para descartar regresiones**

Run: `cd apps/conta && mix test`
Expected: 0 failures.

- [x] **Step 6: Commit**

```bash
git add apps/conta/lib/conta/reconciliation.ex apps/conta/test/conta/reconciliation_context_test.exs
git commit -m "feat: confirm_movements/1 processes a batch independently"
```

---

# FASE 3 — Importadores (Automation)

Sigue el mismo patrón que `Shortcut` (schema, comando, evento, aggregate, projector, LiveView), pero con una única diferencia de comportamiento: el parámetro `movements` (type `table`) es fijo — el formulario no permite añadir/quitar parámetros, solo edita nombre/descripción/código.

## Task 17: Migración + schema de lectura `Automator.Importer`

**Files:**
- Create: migración `create_automator_importers` (mismo shape que `20240627145305_create_automator_filters.exs`, sin columna `output`)
- Create: `apps/conta/lib/conta/projector/automator/importer.ex`

- [x] **Step 1: Generar y escribir la migración**

Run: `cd apps/conta && mix ecto.gen.migration create_automator_importers`

```elixir
defmodule Conta.Repo.Migrations.CreateAutomatorImporters do
  use Ecto.Migration

  def change do
    create table(:automator_importers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :automator, :string
      add :description, :string
      add :code, :text
      add :language, :string
    end

    create unique_index(:automator_importers, [:name, :automator])
  end
end
```

No hay columna `params` — el único parámetro (`movements`, type `table`) es implícito y no se persiste por fila, se construye en memoria al leer (ver Task 18).

Run: `cd apps/conta && mix ecto.migrate`

- [x] **Step 2: Implementar el schema de lectura**

```elixir
defmodule Conta.Projector.Automator.Importer do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder, only: ~w[name automator description code language]a}
  typed_schema "automator_importers" do
    field :name, :string
    field :automator, :string
    field :description, :string
    field :code, :string
    field :language, Ecto.Enum, values: ~w[lua php]a, default: :lua
  end

  @required_fields ~w[name code automator]a
  @optional_fields ~w[language description]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
```

- [x] **Step 3: Commit**

```bash
git add apps/conta/priv/repo/migrations/ apps/conta/lib/conta/projector/automator/importer.ex
git commit -m "feat: add automator_importers table and read-model schema"
```

## Task 18: Comando/evento `SetImporter`/`ImporterSet` y `RemoveImporter`/`ImporterRemoved`

**Files:**
- Create: `apps/conta/lib/conta/command/set_importer.ex`
- Create: `apps/conta/lib/conta/command/remove_importer.ex`
- Create: `apps/conta/lib/conta/event/importer_set.ex`
- Create: `apps/conta/lib/conta/event/importer_removed.ex`

Copiar `set_shortcut.ex` / `remove_shortcut.ex` / `shortcut_set.ex` / `shortcut_removed.ex` quitando por completo el bloque `embeds_many :params` — no hace falta, el parámetro es fijo y se añade en tiempo de ejecución (Task 20), no se persiste.

- [x] **Step 1: `SetImporter`**

```elixir
defmodule Conta.Command.SetImporter do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  typed_embedded_schema do
    field :name, :string
    field :description, :string
    field :automator, :string
    field :code, :string
    field :language, Ecto.Enum, values: ~w[lua php]a, default: :lua
  end

  @required_fields ~w[name automator code]a
  @optional_fields ~w[description language]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  def to_command(changeset), do: apply_changes(changeset)
end
```

- [x] **Step 2: `RemoveImporter`**

```elixir
defmodule Conta.Command.RemoveImporter do
  use TypedEctoSchema

  @primary_key false

  typed_embedded_schema do
    field :name, :string
    field :automator, :string
  end
end
```

- [x] **Step 3: `ImporterSet`**

```elixir
defmodule Conta.Event.ImporterSet do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :name, :string
    field :automator, :string
    field :description, :string
    field :code, :string
    field :language, Ecto.Enum, values: ~w[lua php]a, default: :lua
  end

  @required_fields ~w[name code automator]a
  @optional_fields ~w[language description]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> get_result()
  end
end
```

- [x] **Step 4: `ImporterRemoved`**

```elixir
defmodule Conta.Event.ImporterRemoved do
  use TypedEctoSchema
  import Conta.EctoHelpers
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder
  typed_embedded_schema do
    field :name, :string
    field :automator, :string
  end

  @fields ~w[name automator]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @fields)
    |> validate_required(@fields)
    |> get_result()
  end
end
```

- [x] **Step 5: Commit**

```bash
git add apps/conta/lib/conta/command/set_importer.ex apps/conta/lib/conta/command/remove_importer.ex apps/conta/lib/conta/event/importer_set.ex apps/conta/lib/conta/event/importer_removed.ex
git commit -m "feat: add importer command/event pairs"
```

## Task 19: Extender el aggregate `Automator` con importadores

**Files:**
- Modify: `apps/conta/lib/conta/aggregate/automator.ex`
- Modify: `apps/conta/test/aggregate/automator_test.exs`

- [x] **Step 1: Añadir el test que falla** (mismo patrón que el test de "shortcut" ya existente en ese fichero)

```elixir
  describe "importer" do
    test "create successfully" do
      automator = %Automator{}

      command = %Conta.Command.SetImporter{
        automator: "automator",
        name: "bank x csv",
        code: "-- lua",
        language: "lua"
      }

      event = Automator.execute(automator, command)

      assert %Conta.Event.ImporterSet{automator: "automator", name: "bank x csv", code: "-- lua", language: :lua} = event

      assert %Automator{importers: MapSet.new(["bank x csv"])} == Automator.apply(automator, event)
    end
  end
```

- [x] **Step 2: Ejecutar y comprobar que falla**

Run: `cd apps/conta && mix test test/aggregate/automator_test.exs`
Expected: FAIL

- [x] **Step 3: Implementar**

En `apps/conta/lib/conta/aggregate/automator.ex`, añadir `importers: MapSet.new()` al `defstruct`/`@type`, los `alias` para `SetImporter`/`RemoveImporter`/`ImporterSet`/`ImporterRemoved`, y las cláusulas `execute`/`apply` — copia exacta del patrón de `SetShortcut`/`RemoveShortcut` sustituyendo `shortcuts` por `importers`.

- [x] **Step 4: Ejecutar y comprobar que pasa**

Run: `cd apps/conta && mix test test/aggregate/automator_test.exs`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git add apps/conta/lib/conta/aggregate/automator.ex apps/conta/test/aggregate/automator_test.exs
git commit -m "feat: add importer commands to the Automator aggregate"
```

## Task 20: Router + projector para importadores

**Files:**
- Modify: `apps/conta/lib/conta/commanded/router.ex`
- Modify: `apps/conta/lib/conta/projector/automator.ex`
- Modify: `apps/conta/test/projector/automator_test.exs`

- [x] **Step 1: Registrar `SetImporter`/`RemoveImporter` en el router** (mismo bloque `identify(Automator, ...)` ya existente, añadir las dos líneas `dispatch`)

- [x] **Step 2: Añadir el test de projector que falla** (mismo patrón que el test `"shortcut"` en `projector/automator_test.exs`, para `ImporterSet`/`ImporterRemoved` contra `Automator.Importer`)

- [x] **Step 3: Ejecutar y comprobar que falla**

Run: `cd apps/conta && mix test test/projector/automator_test.exs`

- [x] **Step 4: Implementar los `project(...)` para `ImporterSet`/`ImporterRemoved`** en `Conta.Projector.Automator` — copia exacta del bloque de `ShortcutSet`/`ShortcutRemoved` sin la manipulación de `:params`.

- [x] **Step 5: Ejecutar y comprobar que pasa**

Run: `cd apps/conta && mix test test/projector/automator_test.exs`
Expected: PASS

- [x] **Step 6: Commit**

```bash
git add apps/conta/lib/conta/commanded/router.ex apps/conta/lib/conta/projector/automator.ex apps/conta/test/projector/automator_test.exs
git commit -m "feat: register and project importer commands"
```

## Task 21: Contexto — CRUD de importadores + `run_importer/3`

**Files:**
- Modify: `apps/conta/lib/conta/automator.ex`
- Modify: `apps/conta/test/conta/automator_context_test.exs`
- Create: fixture `importer_factory` en `apps/conta/test/support/fixtures/automator_fixtures.ex`

- [x] **Step 1: Añadir la fixture `importer_factory`** (mismo patrón que `shortcut_factory`, sin `params`)

- [x] **Step 2: Escribir los tests que fallan** (mismo patrón que los de `AutomatorContextTest` para shortcuts: `list_importers/0`, `get_importer/1`, `get_importer_by_name/2` (arity 2 igual que `get_shortcut_by_name/2`, con `automator` por defecto), `get_set_importer/1`, `get_remove_importer/1`, `new_set_importer/0`)

- [x] **Step 3: Ejecutar y comprobar que falla**

Run: `cd apps/conta && mix test test/conta/automator_context_test.exs`

- [x] **Step 4: Implementar los CRUD helpers** en `apps/conta/lib/conta/automator.ex` — copia del patrón de `list_shortcuts/1`, `get_shortcut/2`, `get_shortcut_by_name/2`, `get_set_shortcut/1`, `get_remove_shortcut/1`, `new_set_shortcut/1`, sustituyendo `Shortcut`/`SetShortcut`/`RemoveShortcut` por sus equivalentes de importador (sin el bloque de `params`).

- [x] **Step 5: Escribir el test que falla para `run_importer/3`**

```elixir
  describe "run_importer/3" do
    test "dispatches ImportMovements from the Lua script's movement commands" do
      importer =
        insert(:importer,
          code: """
          function run(params)
            local movements = {}
            for i, row in ipairs(params.movements) do
              movements[i] = {
                type = "movement",
                data = {
                  on_date = row.date,
                  description = row.description,
                  amount = tonumber(row.amount),
                  currency = "EUR"
                }
              }
            end
            return {status = "ok", commands = movements}
          end
          return run(...)
          """
        )

      rows = [%{"date" => "2026-07-01", "description" => "test row", "amount" => "-100"}]

      assert :ok = Automator.run_importer(importer, %{"movements" => rows}, ["Assets", "Bank"])
    end
  end
```

(Ajustar la sintaxis exacta del script Lua al estilo real usado por `Conta.Automator.Lua` — revisar los tests existentes de shortcuts con Lua, p. ej. en `apps/conta/test/conta/automator/lua_test.exs` si existe, antes de dar esto por bueno.)

- [x] **Step 6: Ejecutar y comprobar que falla**

Run: `cd apps/conta && mix test test/conta/automator_context_test.exs`

- [x] **Step 7: Implementar `run_importer/3`**

```elixir
  @movements_param [%Param{name: "movements", type: :table}]

  def run_importer(automator \\ @default_automator, name_or_importer, params, asset_account_name)

  def run_importer(automator, name, params, asset_account_name) when is_binary(name) do
    if importer = get_importer_by_name(automator, name) do
      run_importer(automator, importer, params, asset_account_name)
    else
      {:error, :importer_not_found}
    end
  end

  def run_importer(_automator, %Importer{} = importer, params, asset_account_name) do
    with {:ok, %{"status" => "ok", "commands" => commands}} <- run(importer, params) do
      movements =
        for %{"type" => "movement", "data" => data} <- commands do
          Map.merge(data, %{"asset_account_name" => asset_account_name, "source" => importer.name})
        end

      %{"movements" => movements}
      |> ImportMovements.changeset()
      |> Conta.EctoHelpers.get_result()
      |> case do
        %ImportMovements{} = command -> dispatch(command)
        {:error, _} = error -> error
      end
    end
  end
```

**Nota:** este `changeset/get_result` a nivel del comando padre es el mismo patrón exacto que ya usa `Conta.Automator.process_result/2` para `SetAccountTransaction` (`automator.ex:231-249`) — **no** existe (ni hace falta) un `ImportMovements.Movement.changeset/1` independiente; el `embeds_many :movements` de `Conta.Command.ImportMovements` (Task 4) solo expone su `changeset_movement/2` privado, invocado internamente por `cast_embed/3` cuando se llama a `ImportMovements.changeset/2` sobre el mapa completo, no por elemento.

También revisar si `run/2` (privada, ya usada por `run_shortcut_code/2`) acepta directamente un `%Importer{}` gracias al `def run(%_{code: code, language: :lua}, params)` genérico existente (línea 202 de `automator.ex`) — si es así, no hace falta ninguna cláusula nueva para `run/2`, solo para `run_importer/4`.

- [x] **Step 8: Ejecutar y comprobar que pasa**

Run: `cd apps/conta && mix test test/conta/automator_context_test.exs`
Expected: PASS

- [x] **Step 9: Commit**

```bash
git add apps/conta/lib/conta/automator.ex apps/conta/test/conta/automator_context_test.exs apps/conta/test/support/fixtures/automator_fixtures.ex
git commit -m "feat: importer CRUD and run_importer/4"
```

## Task 22: LiveViews `ImporterLive.Index` / `ImporterLive.Form`

**Files:**
- Create: `apps/conta_web/lib/conta_web/live/importer_live/index.ex` (+ `.heex` si el proyecto separa template)
- Create: `apps/conta_web/lib/conta_web/live/importer_live/form.ex` (+ `.heex`)
- Test: `apps/conta_web/test/conta_web/live/importer_live_test.exs`

Copiar `shortcut_live/index.ex` y `shortcut_live/form.ex` completos (incluyendo sus `.heex`), y simplificar:
- Quitar los eventos `add_param`/`del_param` y el bloque de edición de parámetros en el template — el único parámetro (`movements`, `table`) se muestra fijo, no editable.
- En `apply_action(:new, ...)` construir el `set_importer`/changeset con `params: [%{name: "movements", type: :table}]` fijo si se reutiliza el mismo mecanismo de `test_run` de shortcuts (ver nota de Task 21 sobre `@movements_param`) — o, si `run_importer/4` no necesita `params_defs` (porque el único parámetro es una constante interna del contexto, no algo que el usuario define), el formulario de importador ni siquiera necesita la sección de parámetros del test-run: basta una única textarea fija etiquetada "movements (JSON de prueba)".
- El evento `test_run` llama a una función de contexto equivalente a `test_run_shortcut/3` pero fija a `movements`, p. ej. `Automator.test_run_importer(code, test_movements_json)`.

- [x] **Step 1: Escribir los tests de LiveView que fallan** (mismo patrón que `shortcut_live_test.exs`: listar, crear, editar, borrar — sustituyendo rutas `/automation/shortcuts` por `/automation/importers` y `set_shortcut`/`#shortcut-form` por `set_importer`/`#importer-form`)

- [x] **Step 2: Ejecutar y comprobar que falla**

Run: `cd apps/conta_web && mix test test/conta_web/live/importer_live_test.exs`

- [x] **Step 3: Implementar `ImporterLive.Index` y `ImporterLive.Form`** copiando y adaptando como se describe arriba.

- [x] **Step 4: Ejecutar y comprobar que pasa**

Run: `cd apps/conta_web && mix test test/conta_web/live/importer_live_test.exs`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git add apps/conta_web/lib/conta_web/live/importer_live/ apps/conta_web/test/conta_web/live/importer_live_test.exs
git commit -m "feat: add Importer LiveViews under Automation"
```

**Nota retroactiva:** el scope de rutas `/automation/importers/` tuvo que añadirse en este mismo commit (en `apps/conta_web/lib/conta_web/router.ex`) porque los tests de LiveView usan `live(conn, ~p"/automation/importers...")`, que requiere una ruta real resoluble por el router — no hay forma de probarlo con `live_isolated/3` dado el patrón ya establecido por `shortcut_live_test.exs`. **Task 23 ya NO debe repetir el Step 1** (el scope de rutas ya existe); solo falta la entrada de menú en `app.html.heex`.

## Task 23: Rutas y menú para Importadores

**Files:**
- Modify: `apps/conta_web/lib/conta_web/router.ex`
- Modify: `apps/conta_web/lib/conta_web/components/layouts/app.html.heex`

- [x] **Step 1: Añadir el scope de rutas** (junto al de `/automation/shortcuts/`) — **ya hecho en el commit de la Task 22** (`1ccfccf`), como prerrequisito necesario para que los tests de LiveView pudieran ejecutarse contra rutas reales.

```elixir
      scope "/automation/importers/" do
        live "/", ImporterLive.Index, :index
        live "/new", ImporterLive.Form, :new
        live "/:id/edit", ImporterLive.Form, :edit
      end
```

- [x] **Step 2: Añadir la entrada de menú** dentro de `<.navbar_dropdown name={gettext("Automation")}>`, junto a Filters/Shortcuts:

```heex
      <.navbar_item href={~p"/automation/importers"}>{gettext("Importers")}</.navbar_item>
```

- [ ] **Step 3: Verificación manual** (pendiente — requiere confirmación explícita del usuario antes de arrancar/parar `mix phx.server`)

Levantar el servidor (`mix phx.server`, si no está ya corriendo — confirmar con el usuario antes de arrancarlo/pararlo) y comprobar en el navegador que "Automation → Importers" aparece y navega a la lista.

- [x] **Step 4: Commit**

```bash
git add apps/conta_web/lib/conta_web/components/layouts/app.html.heex
git commit -m "feat: expose Importers under Automation menu"
```

---

# FASE 4 — Pantalla de subida (Ledger → Conciliación)

## Task 24: Dependencia NimbleCSV

**Files:**
- Modify: `apps/conta/mix.exs`

- [x] **Step 1: Añadir la dependencia** junto a `{:elixlsx, "~> 0.6"}`

```elixir
      {:nimble_csv, "~> 1.2"},
```

- [x] **Step 2: Instalar**

Run: `cd apps/conta && mix deps.get`

- [x] **Step 3: Commit**

```bash
git add apps/conta/mix.exs apps/conta/mix.lock
git commit -m "feat: add nimble_csv dependency"
```

## Task 25: Parser CSV → tabla de filas

**Files:**
- Create: `apps/conta/lib/conta/reconciliation/csv_import.ex`
- Test: `apps/conta/test/conta/reconciliation/csv_import_test.exs`

- [x] **Step 1: Escribir el test que falla**

```elixir
defmodule Conta.Reconciliation.CsvImportTest do
  use ExUnit.Case

  alias Conta.Reconciliation.CsvImport

  test "parses a CSV binary into a list of maps keyed by header" do
    csv = "date,description,amount\n2026-07-01,NETFLIX,-13.99\n2026-07-02,SALARY,1500.00\n"

    assert {:ok, rows} = CsvImport.parse(csv)

    assert rows == [
             %{"date" => "2026-07-01", "description" => "NETFLIX", "amount" => "-13.99"},
             %{"date" => "2026-07-02", "description" => "SALARY", "amount" => "1500.00"}
           ]
  end

  test "returns an error for an empty file" do
    assert {:error, :empty_file} = CsvImport.parse("")
  end
end
```

- [x] **Step 2: Ejecutar y comprobar que falla**

Run: `cd apps/conta && mix test test/conta/reconciliation/csv_import_test.exs`

- [x] **Step 3: Implementar**

```elixir
defmodule Conta.Reconciliation.CsvImport do
  NimbleCSV.define(Parser, separator: ",", escape: "\"")

  def parse(""), do: {:error, :empty_file}

  def parse(binary) when is_binary(binary) do
    [header | rows] = Parser.parse_string(binary, skip_headers: false)

    rows =
      Enum.map(rows, fn row ->
        header
        |> Enum.zip(row)
        |> Map.new()
      end)

    {:ok, rows}
  end
end
```

- [x] **Step 4: Ejecutar y comprobar que pasa**

Run: `cd apps/conta && mix test test/conta/reconciliation/csv_import_test.exs`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git add apps/conta/lib/conta/reconciliation/csv_import.ex apps/conta/test/conta/reconciliation/csv_import_test.exs
git commit -m "feat: add CSV parsing for bank statement uploads"
```

**Nota retroactiva:** se añadió un commit de corrección (`ff15f29`, "fix: reject CSV rows with mismatched column counts") tras la revisión de calidad — `Enum.zip(header, row)` truncaba silenciosamente filas con recuento de columnas distinto al de la cabecera. Ahora `parse/1` devuelve `{:error, {:column_mismatch, line}}` (line = número de línea 1-based, contando la cabecera como línea 1) y aborta en la primera fila mal formada.

## Task 26: LiveView de subida (`ReconciliationLive.Upload`)

**Files:**
- Create: `apps/conta_web/lib/conta_web/live/reconciliation_live/upload.ex` (+ `.heex`)
- Test: `apps/conta_web/test/conta_web/live/reconciliation_live/upload_test.exs`

Usar `Phoenix.LiveView.Upload` (`allow_upload/3`, `consume_uploaded_entries/3`) — patrón estándar de Phoenix, sin precedente directo en este codebase; seguir la documentación oficial de LiveView para la mecánica de subida de fichero, y las convenciones locales (`use ContaWeb, :live_view`, `gettext`, `~p` sigils, `to_form`) para todo lo demás.

- [x] **Step 1: Escribir el test que falla**

```elixir
defmodule ContaWeb.ReconciliationLive.UploadTest do
  use ContaWeb.ConnCase
  import Phoenix.LiveViewTest
  import Commanded.Assertions.EventAssertions
  import Conta.AutomatorFixtures
  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.AccountsFixtures
  alias Conta.Command.SetAccount
  alias Conta.Event.MovementsImported

  setup do
    user = AccountsFixtures.insert(:user) |> AccountsFixtures.confirm_user()
    bank_name = ["Assets", "Bank #{System.unique_integer([:positive])}"]
    :ok = dispatch(%SetAccount{name: bank_name, type: :assets, currency: :EUR, ledger: "default"})

    importer =
      insert(:importer,
        code: """
        function run(params)
          local movements = {}
          for i, row in ipairs(params.movements) do
            movements[i] = {type = "movement", data = {on_date = row.date, description = row.description, amount = tonumber(row.amount) * 100, currency = "EUR"}}
          end
          return {status = "ok", commands = movements}
        end
        return run(...)
        """
      )

    :ok = dispatch(Conta.Automator.get_set_importer(importer))

    %{user: user, bank_name: bank_name, importer: importer}
  end

  test "uploads a CSV, runs the importer and redirects to the review screen", %{conn: conn, user: user, bank_name: bank_name, importer: importer} do
    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/ledger/reconciliation/upload")

    csv = "date,description,amount\n2026-07-01,NETFLIX,-13.99\n"

    file =
      file_input(view, "#upload-form", :statement, [
        %{name: "statement.csv", content: csv, type: "text/csv"}
      ])

    render_upload(file, "statement.csv")

    result =
      view
      |> form("#upload-form", %{"importer_name" => importer.name, "asset_account_name" => Enum.join(bank_name, ".")})
      |> render_submit()

    wait_for_event(Conta.Commanded.Application, MovementsImported)

    assert {:ok, _review_live, html} = follow_redirect(result, conn, ~p"/ledger/reconciliation")
    assert html =~ "NETFLIX"
  end
end
```

- [x] **Step 2: Ejecutar y comprobar que falla**

Run: `cd apps/conta_web && mix test test/conta_web/live/reconciliation_live/upload_test.exs`

- [x] **Step 3: Implementar `ReconciliationLive.Upload`**

```elixir
defmodule ContaWeb.ReconciliationLive.Upload do
  use ContaWeb, :live_view

  alias Conta.Automator
  alias Conta.Ledger
  alias Conta.Reconciliation.CsvImport

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Upload bank statement"))
     |> assign(:importers, Automator.list_importers())
     |> assign(:asset_accounts, Ledger.list_accounts(:assets))
     |> assign(:error, nil)
     |> allow_upload(:statement, accept: ~w(.csv), max_entries: 1)}
  end

  @impl true
  def handle_event("save", %{"importer_name" => importer_name, "asset_account_name" => asset_account_name}, socket) do
    with [csv] <- consume_uploaded_entries(socket, :statement, fn %{path: path}, _entry -> {:ok, File.read!(path)} end),
         {:ok, rows} <- CsvImport.parse(csv),
         asset_account_name = String.split(asset_account_name, "."),
         :ok <- Automator.run_importer(importer_name, %{"movements" => rows}, asset_account_name) do
      {:noreply, push_navigate(socket, to: ~p"/ledger/reconciliation")}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, inspect(reason))}
      [] -> {:noreply, assign(socket, :error, gettext("Please choose a file"))}
    end
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}
end
```

- [x] **Step 4: Implementar el template** (`upload.html.heex`) — formulario `#upload-form` con `<.live_file_input upload={@uploads.statement} />`, `<select name="importer_name">` listando `@importers`, `<select name="asset_account_name">` listando `@asset_accounts` (value = cuenta unida por `.`), botón submit "Subir e importar", y `@error` mostrado si presente.

- [x] **Step 5: Ejecutar y comprobar que pasa**

Run: `cd apps/conta_web && mix test test/conta_web/live/reconciliation_live/upload_test.exs`
Expected: PASS

- [x] **Step 6: Commit**

```bash
git add apps/conta_web/lib/conta_web/live/reconciliation_live/upload.ex apps/conta_web/lib/conta_web/live/reconciliation_live/upload.html.heex apps/conta_web/test/conta_web/live/reconciliation_live/upload_test.exs
git commit -m "feat: add bank statement upload screen"
```

**Notas retroactivas:**
- El scope de rutas `/ledger/reconciliation/upload` tuvo que añadirse en este mismo commit (`a6467aa`, `apps/conta_web/lib/conta_web/router.ex`) porque el test de LiveView requiere una ruta real resoluble — mismo motivo que en la Task 22. **Task 27 ya NO debe repetir el Step 1** (el scope ya existe); solo falta la entrada de menú en `app.html.heex`.
- No existe aún la pantalla de Revisión (Task 30), así que en vez de `push_navigate` a `/ledger/reconciliation`, el flujo de éxito se queda en la misma página y muestra un mensaje "Imported N movements" (patrón "ejecutar y mostrar resultado inline" ya usado en `ImporterLive.Form`). Cuando la Task 30 exista, valorar si conviene redirigir a la pantalla de revisión en su lugar.
- Commit de corrección posterior (`4a74e73`) tras revisión de calidad: se sustituyó el markup manual del input de fichero por el componente `<.input type="file">` ya establecido en la app (usado por `expense_live`), se generalizó el resultado mostrado (ya no asume columnas CSV fijas `date`/`description`/`amount`), y se añadió cobertura de tests para las ramas de error del `with/else` (sin fichero, CSV vacío, desajuste de columnas).

## Task 27: Rutas y menú para Conciliación (subida)

**Files:**
- Modify: `apps/conta_web/lib/conta_web/router.ex`
- Modify: `apps/conta_web/lib/conta_web/components/layouts/app.html.heex`

- [x] **Step 1: Añadir el scope de rutas** — **ya hecho en el commit de la Task 26** (`a6467aa`), como prerrequisito necesario para el test de LiveView.

```elixir
      scope "/ledger/reconciliation/" do
        live "/upload", ReconciliationLive.Upload, :new
      end
```

- [x] **Step 2: Añadir la entrada de menú** dentro de `<.navbar_dropdown name={gettext("Ledger")}>`:

```heex
      <.navbar_item href={~p"/ledger/reconciliation/upload"}>{gettext("Reconciliation")}</.navbar_item>
```

- [x] **Step 3: Commit**

```bash
git add apps/conta_web/lib/conta_web/components/layouts/app.html.heex
git commit -m "feat: expose bank statement upload under Ledger menu"
```

---

# FASE 5 — Pantalla de Concordancias

## Task 28: LiveViews `ReconciliationLive.Matches` (listado + formulario + reordenar)

**Files:**
- Create: `apps/conta_web/lib/conta_web/live/reconciliation_live/matches.ex` (+ `.heex`)
- Test: `apps/conta_web/test/conta_web/live/reconciliation_live/matches_test.exs`

Copiar la estructura general de `shortcut_live/index.ex` (listado + acciones inline de crear/editar/borrar en una sola LiveView, ya que aquí no hay Lua ni test-run, es un CRUD más simple) y el patrón de `add_param`/`del_param` de `shortcut_live/form.ex` para el `handle_event` de "añadir condición"/"quitar condición" dentro del formulario de una regla.

- [x] **Step 1: Escribir los tests que fallan** — cubrir: listar reglas, crear una regla con una condición, editar, borrar, reordenar (dos clics en botones "subir"/"bajar" o drag — para LiveViewTest, más simple exponer botones "mover arriba"/"mover abajo" que un drag real).

- [x] **Step 2: Ejecutar y comprobar que falla**

Run: `cd apps/conta_web && mix test test/conta_web/live/reconciliation_live/matches_test.exs`

- [x] **Step 3: Implementar `ReconciliationLive.Matches`**

Puntos clave de la implementación:
- `handle_event("save", %{"set_match_rule" => params}, socket)` → `SetMatchRule.changeset/2` → `dispatch/1`, igual que `ShortcutLive.Form`.
- `handle_event("delete", %{"id" => id}, socket)` → `dispatch(%RemoveMatchRule{id: id})`.
- `handle_event("move_up"/"move_down", %{"id" => id}, socket)` → calcula la nueva lista de ids a partir de `Reconciliation.list_match_rules/0` y despacha `%ReorderMatchRules{ids: new_order}`.
- Formulario de condiciones: `add_condition`/`del_condition` copiando `add_param`/`del_param` de `shortcut_live/form.ex:54-77`.

- [x] **Step 4: Ejecutar y comprobar que pasa**

Run: `cd apps/conta_web && mix test test/conta_web/live/reconciliation_live/matches_test.exs`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git add apps/conta_web/lib/conta_web/live/reconciliation_live/matches.ex apps/conta_web/lib/conta_web/live/reconciliation_live/matches.html.heex apps/conta_web/test/conta_web/live/reconciliation_live/matches_test.exs
git commit -m "feat: add match rules management screen"
```

**Notas retroactivas:**
- Implementado como split Index+Form (`reconciliation_live/matches/index.ex` + `form.ex`), no como LiveView única, por consistencia con `ImporterLive`/`ShortcutLive`/`FilterLive` (el plan sugería una sola vista por simplicidad, pero la convención establecida en el resto de la app pesó más).
- El scope de rutas `/ledger/reconciliation/matches` tuvo que añadirse en este mismo commit (`f084754`, mismo scope que ya creó la Task 26) porque el test de LiveView requiere rutas reales. **Task 29 ya NO debe repetir el Step 1**; solo falta la entrada de menú en `app.html.heex`.
- Se encontró y corrigió una condición de carrera real de eventual consistency en `move_up`/`move_down`: en vez de releer `Reconciliation.list_match_rules/0` justo después de `dispatch/1` (podría ver el orden aún no proyectado), se reordena localmente la lista en memoria del LiveView, manteniendo el dispatch como la escritura autoritativa para la siguiente carga de página.
- Commit de corrección posterior (`58454b0`) tras revisión de calidad: test de regresión para "Añadir condición" como primera acción en edición (evita perder las condiciones existentes), corrección de un docstring incorrecto en `get_set_match_rule/1`, y recálculo de `.position` tras reordenar.
- Se documentó en `TODO.md` un warning latente de Ecto (ids duplicados en el embed `conditions`) encontrado durante esa revisión — no bloqueante, pendiente de revisión futura.

## Task 29: Rutas y menú para Concordancias

**Files:**
- Modify: `apps/conta_web/lib/conta_web/router.ex`
- Modify: `apps/conta_web/lib/conta_web/components/layouts/app.html.heex`

- [x] **Step 1: Añadir la ruta** dentro del scope `/ledger/reconciliation/` creado en la Fase 4 — **ya hecho en el commit de la Task 28** (`f084754`).

```elixir
        live "/matches", ReconciliationLive.Matches, :index
```

- [x] **Step 2: Añadir la entrada de menú**

```heex
      <.navbar_item href={~p"/ledger/reconciliation/matches"}>{gettext("Matches")}</.navbar_item>
```

- [x] **Step 3: Commit**

```bash
git add apps/conta_web/lib/conta_web/router.ex apps/conta_web/lib/conta_web/components/layouts/app.html.heex
git commit -m "feat: expose match rules screen under Ledger menu"
```

---

# FASE 6 — Pantalla de Revisión

## Task 30: LiveView `ReconciliationLive.Review`

**Files:**
- Create: `apps/conta_web/lib/conta_web/live/reconciliation_live/review.ex` (+ `.heex`)
- Test: `apps/conta_web/test/conta_web/live/reconciliation_live/review_test.exs`

Esta es la pantalla que junta todo. Revisar la sección "Ledger → Revisión" del spec (`docs/superpowers/specs/2026-07-11-bank-reconciliation-design.md`) antes de implementar — en particular el tratamiento especial de filas con `transacted: true` (sin checkbox, sin edición inline, botón "Eliminar" reproposeado como reintento de `RemoveMovement`).

- [x] **Step 1: Escribir los tests que fallan.** Cubrir, como mínimo:
  - Un movimiento con `account_name` aparece en el bloque superior con checkbox; uno sin `account_name`, en el inferior sin checkbox.
  - Asignar cuenta a uno del bloque inferior (vía `handle_event("update_account", ...)` → `Reconciliation.update_movement/2`) lo mueve al bloque superior tras el siguiente render.
  - Seleccionar checkboxes y pulsar "Confirmar" invoca `Reconciliation.confirm_movements/1` y desaparecen de la lista los confirmados con éxito; los fallidos permanecen con un mensaje de error visible en su fila.
  - Un movimiento con `transacted: true` no muestra checkbox ni controles de edición inline, y su botón "Eliminar" dispara `Reconciliation.confirm_movement/1` de nuevo (que internamente solo reintenta el paso de retirada, per Task 15) en vez de `RemoveMovement` directo.
  - Eliminar una fila normal (sin `transacted`) dispatcha `RemoveMovement` directamente.

- [x] **Step 2: Ejecutar y comprobar que falla**

Run: `cd apps/conta_web && mix test test/conta_web/live/reconciliation_live/review_test.exs`

- [x] **Step 3: Implementar `ReconciliationLive.Review`**

Puntos clave:
- `mount/3` carga `Reconciliation.list_movements/0` y las separa en `Enum.split_with(&(&1.account_name != nil))` para los dos bloques — recalcular en cada `handle_event` que muta datos (o suscribirse vía PubSub si el proyector ya hace broadcast, siguiendo el patrón de `after_update` visto en `projector/ledger.ex:252-282`; si se opta por PubSub, añadir el broadcast correspondiente al `Conta.Projector.Reconciliation` como parte de este task).
- `handle_event("confirm", %{"ids" => ids}, socket)` → `Reconciliation.confirm_movements/1`, refresca la lista, y anota los errores por fila (`assign(:errors, %{id => reason})`) para las que fallaron.
- `handle_event("remove", %{"id" => id}, socket)`:
  ```elixir
  movement = Enum.find(socket.assigns.movements, &(&1.id == id))

  if movement.transacted do
    Reconciliation.confirm_movement(id)
  else
    dispatch(%RemoveMovement{id: id})
  end
  ```
- `handle_event("update_field", %{"id" => id, "field" => field, "value" => value}, socket)` (deshabilitado en el template para filas `transacted: true`) → `Reconciliation.update_movement(id, %{field => value})`.

- [x] **Step 4: Implementar el template** (`review.html.heex`) — dos tablas (bloque superior/inferior) más la fila especial `transacted`, checkboxes con `phx-click` acumulando selección en el socket assign, botón "Confirmar" con `phx-click="confirm"` pasando los ids seleccionados.

- [x] **Step 5: Ejecutar y comprobar que pasa**

Run: `cd apps/conta_web && mix test test/conta_web/live/reconciliation_live/review_test.exs`
Expected: PASS

- [x] **Step 6: Commit**

```bash
git add apps/conta_web/lib/conta_web/live/reconciliation_live/review.ex apps/conta_web/lib/conta_web/live/reconciliation_live/review.html.heex apps/conta_web/test/conta_web/live/reconciliation_live/review_test.exs
git commit -m "feat: add reconciliation review screen"
```

**Notas retroactivas:**
- El scope de rutas tuvo que extenderse en este mismo commit (`75efd7d`, añadiendo `live "/", ReconciliationLive.Review, :index` al scope `/ledger/reconciliation/` ya existente) porque el test de LiveView requiere una ruta real. **Task 31 ya NO debe repetir ese paso.**
- Diseño sin PubSub ni re-consulta tras dispatch: cada `handle_event` que muta datos actualiza `socket.assigns.movements` de forma optimista en memoria (vía `Movement.changeset/2` + `apply_action/2`), evitando la misma condición de carrera de `:consistency` ya documentada en `TODO.md` y ya resuelta así en la Task 28.
- Commit de corrección (`a05a672`) tras revisión de calidad: se encontró y corrigió un bug **crítico** reproducido en vivo — desasignar una cuenta vía la opción "(No account)" del desplegable fallaba en persistir silenciosamente (el estado optimista local divergía del real en BD). La especificación solo requiere *asignar* cuenta (nunca desasignar), así que se eliminó esa opción de la UI en vez de tocar la ambigüedad ya documentada en el aggregate (`changes: %{"account_name" => nil}` tratado como "campo sin tocar"). También se corrigió que un fallo parcial de `confirm_movements/1` (transacción creada pero `RemoveMovement` fallido) no se reflejaba localmente, y se añadió cobertura de test que faltaba y dejó pasar el bug crítico sin detectar.

## Task 31: Rutas y menú para Revisión + verificación manual final

**Files:**
- Modify: `apps/conta_web/lib/conta_web/router.ex`
- Modify: `apps/conta_web/lib/conta_web/components/layouts/app.html.heex`

- [x] **Step 1: Añadir la ruta** dentro del scope `/ledger/reconciliation/` — **ya hecho en el commit de la Task 30** (`75efd7d`).

```elixir
        live "/", ReconciliationLive.Review, :index
```

- [x] **Step 2: Añadir la entrada de menú**

```heex
      <.navbar_item href={~p"/ledger/reconciliation"}>{gettext("Review")}</.navbar_item>
```

- [x] **Step 3: Ejecutar la suite completa de ambas apps**

Run: `mix test` (desde la raíz del umbrella)
Expected: 0 failures.

Resultado: **497 tests, 0 failures** (conta 343/0, conta_web 154/0/11 excluded), verificado de forma independiente por el revisor.

- [ ] **Step 4: Verificación manual end-to-end** (pendiente — requiere al usuario en el navegador)

Con el servidor levantado (preguntado y confirmado por el usuario — arrancado en `http://127.0.0.1:4000`, log en `/tmp/conta_phx_server.log`), recorrer el flujo completo en el navegador: crear una cuenta assets y una expenses de prueba → crear un importador simple en Automation → crear una regla de match en Ledger → Concordancias → subir un CSV pequeño en Ledger → Conciliación → confirmar un movimiento en Ledger → Revisión → comprobar que la transacción aparece en la cuenta correspondiente.

Smoke-test automático (sin navegador, vía curl) ya realizado: `/automation/importers`, `/ledger/reconciliation/upload`, `/ledger/reconciliation/matches` y `/ledger/reconciliation` devuelven `302` (redirect limpio a `/signin`, sin error 500); `/` devuelve `200`. Confirma que el enrutado funciona en un servidor real, pero no sustituye la verificación funcional interactiva (crear/editar/confirmar), que queda pendiente de que el usuario la haga manualmente.

- [x] **Step 5: Commit**

```bash
git add apps/conta_web/lib/conta_web/components/layouts/app.html.heex
git commit -m "feat: expose reconciliation review screen under Ledger menu"
```
