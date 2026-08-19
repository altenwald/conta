defmodule Conta.Aggregate.Reconciliation do
  alias Conta.Command.ImportMovements
  alias Conta.Command.MarkMovementTransacted
  alias Conta.Command.RemoveMatchRule
  alias Conta.Command.RemoveMovement
  alias Conta.Command.RematchMovements
  alias Conta.Command.ReorderMatchRules
  alias Conta.Command.SetMatchRule
  alias Conta.Command.UpdateMovement

  alias Conta.Event.MatchRuleRemoved
  alias Conta.Event.MatchRuleSet
  alias Conta.Event.MatchRulesReordered
  alias Conta.Event.MovementRemoved
  alias Conta.Event.MovementsImported
  alias Conta.Event.MovementTransacted
  alias Conta.Event.MovementUpdated

  @derive Jason.Encoder

  @type match_rule() :: %{
          id: String.t(),
          name: String.t(),
          conditions: list(),
          match_type: :all | :any,
          account_name: [String.t()],
          concept: String.t() | nil
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

  def execute(%__MODULE__{match_rules: match_rules}, %SetMatchRule{id: id} = command) do
    if Enum.any?(match_rules, &(&1.id == id)) do
      build_match_rule_set(command, id)
    else
      {:error, %{id: ["not found"]}}
    end
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
    existing_ids = match_rules |> Enum.map(& &1.id) |> MapSet.new()

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

  # `MovementsImported.changeset/2` (Task 5) already ends its own pipeline with
  # `|> get_result()`, so it returns the resolved `%MovementsImported{}` struct or
  # `{:error, errors}` directly — piping that into `Conta.EctoHelpers.get_result/1`
  # again would raise, since `get_result/1` requires a raw `%Ecto.Changeset{}`, not an
  # already-resolved struct. Do not add a trailing `get_result()` call here.
  def execute(%__MODULE__{match_rules: match_rules}, %ImportMovements{movements: movements}) do
    movements =
      Enum.map(movements, fn movement ->
        {account_name, description} = evaluate_rules(match_rules, movement)

        movement
        |> Map.from_struct()
        |> Map.put(:id, Ecto.UUID.generate())
        |> Map.put(:account_name, account_name)
        |> Map.put(:description, description)
        |> Map.put(:transacted, false)
      end)

    %{movements: movements}
    |> MovementsImported.changeset()
  end

  # `MovementUpdated.changeset/2` (Task 5) also ends its own pipeline with
  # `|> get_result()`, so the same reasoning as above applies: do not pipe its
  # result into `Conta.EctoHelpers.get_result/1` again.
  def execute(%__MODULE__{movements: movements, match_rules: match_rules}, %UpdateMovement{
        id: id,
        changes: changes
      }) do
    case movements[id] do
      nil ->
        {:error, %{id: ["not found"]}}

      %{transacted: true} ->
        {:error, %{id: ["already transacted"]}}

      movement ->
        case apply_changes_to_movement(movement, changes) do
          {:error, errors} ->
            {:error, errors}

          {:ok, updated} ->
            # `nil` here means "no change to account_name" (see `apply/2` below), not
            # "unassign" — when the movement already has an account_name and the edit
            # doesn't touch it directly, we leave it untouched rather than re-stamping
            # the current value into the event. Note this also means an explicit
            # `changes: %{"account_name" => nil}` ("unassign") is indistinguishable
            # from "didn't touch it" and is a no-op today — there's no sentinel yet
            # for a deliberate clear; that's a known gap, not a bug, until an
            # "unassign" UI action needs it.
            {account_name, description} =
              cond do
                Map.has_key?(changes, "account_name") -> {updated.account_name, updated.description}
                is_nil(movement.account_name) -> evaluate_rules(match_rules, updated)
                :else -> {nil, updated.description}
              end

            %{
              id: id,
              on_date: updated.on_date,
              description: description,
              amount: updated.amount,
              currency: updated.currency,
              account_name: account_name
            }
            |> MovementUpdated.changeset()
        end
    end
  end

  def execute(%__MODULE__{movements: movements, match_rules: match_rules}, %RematchMovements{ids: ids}) do
    events =
      for id <- ids,
          movement = Map.get(movements, id),
          movement != nil,
          not movement.transacted do
        {account_name, description} = evaluate_rules(match_rules, movement)

        if account_name != movement.account_name or description != movement.description do
          %{
            id: id,
            on_date: movement.on_date,
            description: description,
            amount: movement.amount,
            currency: movement.currency,
            account_name: account_name
          }
          |> MovementUpdated.changeset()
        end
      end
      |> Enum.reject(&is_nil/1)

    case events do
      [] -> :ok
      _ -> events
    end
  end

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

  # Returns `{:ok, movement}` with the parsed changes merged in, or
  # `{:error, %{field => [reason]}}` the moment a *provided, non-nil* value fails
  # to cast. We deliberately reject the whole update rather than falling back to
  # the old value on a bad cast: on_date/amount/currency are financial fields
  # with no downstream fallback (unlike account_name, which has an explicit `nil`
  # sentinel), so silently keeping a stale value the caller didn't ask to keep
  # would be worse than failing loudly.
  defp apply_changes_to_movement(movement, changes) do
    with {:ok, movement} <- put_cast(movement, :on_date, changes["on_date"], &parse_date/1),
         {:ok, movement} <- put_raw(movement, :description, changes["description"]),
         {:ok, movement} <- put_cast(movement, :amount, changes["amount"], &parse_integer/1),
         {:ok, movement} <- put_cast(movement, :currency, changes["currency"], &parse_currency/1),
         {:ok, movement} <- put_raw(movement, :account_name, changes["account_name"]) do
      {:ok, movement}
    end
  end

  defp put_raw(map, _key, nil), do: {:ok, map}
  defp put_raw(map, key, value), do: {:ok, Map.put(map, key, value)}

  defp put_cast(map, _key, nil, _cast_fun), do: {:ok, map}

  defp put_cast(map, key, value, cast_fun) do
    case cast_fun.(value) do
      nil -> {:error, %{key => ["is invalid"]}}
      parsed -> {:ok, Map.put(map, key, parsed)}
    end
  end

  defp parse_currency(value) do
    case Money.Ecto.Currency.Type.cast(value) do
      {:ok, currency} -> currency
      :error -> nil
    end
  end

  def evaluate_rules(match_rules, movement) do
    Enum.find_value(match_rules, {nil, movement.description}, fn rule ->
      if rule_matches?(rule, movement) do
        {rule.account_name, transform_description(rule, movement.description)}
      end
    end)
  end

  defp transform_description(%{concept: concept} = rule, original_description)
       when is_binary(concept) and concept != "" do
    regex_condition =
      Enum.find(rule.conditions, fn
        %{field: :description, comparator: :regex, value: value} when is_binary(value) -> true
        %{"field" => "description", "comparator" => "regex", "value" => value} when is_binary(value) -> true
        _ -> false
      end)

    case regex_condition do
      nil ->
        concept

      cond_map ->
        val =
          if is_map(cond_map) and Map.has_key?(cond_map, :value),
            do: cond_map.value,
            else: cond_map["value"]

        case Regex.compile(val) do
          {:ok, regex} ->
            case Regex.run(regex, original_description || "") do
              nil ->
                concept

              [full_match | captures] ->
                captures
                |> Enum.with_index(1)
                |> Enum.reduce(concept, fn {cap, idx}, acc ->
                  acc
                  |> String.replace("\\#{idx}", cap)
                  |> String.replace("$#{idx}", cap)
                end)
                |> String.replace("\\0", full_match)
                |> String.replace("$0", full_match)
            end

          {:error, _} ->
            concept
        end
    end
  end

  defp transform_description(_rule, original_description), do: original_description

  defp rule_matches?(%{conditions: conditions, match_type: match_type}, movement)
       when match_type in [:all, "all"] do
    Enum.all?(conditions, &condition_matches?(&1, movement))
  end

  defp rule_matches?(%{conditions: conditions, match_type: match_type}, movement)
       when match_type in [:any, "any"] do
    Enum.any?(conditions, &condition_matches?(&1, movement))
  end

  defp condition_matches?(condition, movement) when is_map(condition) do
    field = cond_val(condition, :field)
    comp = cond_val(condition, :comparator)
    value = cond_val(condition, :value)
    value_to = cond_val(condition, :value_to)

    match_field_comparator(field, comp, value, value_to, movement)
  end

  defp condition_matches?(_condition, _movement), do: false

  defp cond_val(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp match_field_comparator(field, comp, value, _value_to, movement)
       when field in [:description, "description"] and comp in [:contains, "contains"] do
    String.contains?(movement.description || "", to_string(value))
  end

  defp match_field_comparator(field, comp, value, _value_to, movement)
       when field in [:description, "description"] and comp in [:equals, "equals"] do
    (movement.description || "") == to_string(value)
  end

  defp match_field_comparator(field, comp, value, _value_to, movement)
       when field in [:description, "description"] and comp in [:regex, "regex"] do
    case Regex.compile(to_string(value)) do
      {:ok, regex} -> Regex.match?(regex, movement.description || "")
      {:error, _} -> false
    end
  end

  defp match_field_comparator(field, comp, value, _value_to, movement)
       when field in [:amount, "amount"] and comp in [:equals, "equals"] do
    case parse_integer(value) do
      nil -> false
      parsed -> movement.amount == parsed
    end
  end

  defp match_field_comparator(field, comp, value, _value_to, movement)
       when field in [:amount, "amount"] and comp in [:greater_than, "greater_than"] do
    case parse_integer(value) do
      nil -> false
      parsed -> movement.amount > parsed
    end
  end

  defp match_field_comparator(field, comp, value, _value_to, movement)
       when field in [:amount, "amount"] and comp in [:less_than, "less_than"] do
    case parse_integer(value) do
      nil -> false
      parsed -> movement.amount < parsed
    end
  end

  defp match_field_comparator(field, comp, value, _value_to, movement)
       when field in [:on_date, "on_date"] and comp in [:equals, "equals"] do
    case parse_date(value) do
      nil -> false
      parsed -> movement.on_date == parsed
    end
  end

  defp match_field_comparator(field, comp, from, to, movement)
       when field in [:on_date, "on_date"] and comp in [:between, "between"] do
    from = parse_date(from)
    to = parse_date(to)

    not is_nil(from) and not is_nil(to) and Date.compare(movement.on_date, from) != :lt and
      Date.compare(movement.on_date, to) != :gt
  end

  defp match_field_comparator(_field, _comp, _val, _val_to, _movement), do: false

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    cleaned = String.trim(value)

    cond do
      String.contains?(cleaned, ".") or String.contains?(cleaned, ",") ->
        case Float.parse(String.replace(cleaned, ",", ".")) do
          {f, ""} -> round(f * 100)
          _ -> nil
        end

      match?({_, ""}, Integer.parse(cleaned)) ->
        String.to_integer(cleaned)

      true ->
        nil
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
      account_name: event.account_name,
      concept: event.concept
    }

    {match_rules, found?} =
      Enum.map_reduce(match_rules, false, fn
        %{id: id}, _found? when id == rule.id -> {rule, true}
        existing, found? -> {existing, found?}
      end)

    match_rules = if found?, do: match_rules, else: match_rules ++ [rule]

    %__MODULE__{reconciliation | match_rules: match_rules}
  end

  def apply(%__MODULE__{match_rules: match_rules} = reconciliation, %MatchRuleRemoved{id: id}) do
    %__MODULE__{reconciliation | match_rules: Enum.reject(match_rules, &(&1.id == id))}
  end

  def apply(%__MODULE__{match_rules: match_rules} = reconciliation, %MatchRulesReordered{ids: ids}) do
    by_id = Map.new(match_rules, &{&1.id, &1})
    %__MODULE__{reconciliation | match_rules: Enum.map(ids, &by_id[&1])}
  end

  def apply(%__MODULE__{movements: movements} = reconciliation, %MovementsImported{movements: imported}) do
    new_movements =
      Map.new(imported, fn movement ->
        {movement.id, Map.from_struct(movement)}
      end)

    %__MODULE__{reconciliation | movements: Map.merge(movements, new_movements)}
  end

  def apply(%__MODULE__{movements: movements} = reconciliation, %MovementUpdated{} = event) do
    movements =
      Map.update!(movements, event.id, fn movement ->
        movement
        |> Map.put(:on_date, event.on_date)
        |> Map.put(:description, event.description)
        |> Map.put(:amount, event.amount)
        |> Map.put(:currency, event.currency)
        # `event.account_name` is `nil` when `execute/2` decided the account_name
        # shouldn't be touched (see the comment there) — keep the movement's
        # current value in that case instead of wiping it out.
        |> Map.put(:account_name, event.account_name || movement.account_name)
      end)

    %__MODULE__{reconciliation | movements: movements}
  end

  def apply(%__MODULE__{movements: movements} = reconciliation, %MovementRemoved{id: id}) do
    %__MODULE__{reconciliation | movements: Map.delete(movements, id)}
  end

  def apply(%__MODULE__{movements: movements} = reconciliation, %MovementTransacted{id: id}) do
    %__MODULE__{reconciliation | movements: Map.update!(movements, id, &Map.put(&1, :transacted, true))}
  end

  def apply(reconciliation, _event), do: reconciliation
end
