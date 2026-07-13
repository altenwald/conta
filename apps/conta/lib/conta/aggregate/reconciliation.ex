defmodule Conta.Aggregate.Reconciliation do
  alias Conta.Command.ImportMovements
  alias Conta.Command.MarkMovementTransacted
  alias Conta.Command.RemoveMatchRule
  alias Conta.Command.RemoveMovement
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
        movement
        |> Map.from_struct()
        |> Map.put(:id, Ecto.UUID.generate())
        |> Map.put(:account_name, evaluate_rules(match_rules, movement))
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
            account_name =
              cond do
                Map.has_key?(changes, "account_name") -> updated.account_name
                is_nil(movement.account_name) -> evaluate_rules(match_rules, updated)
                :else -> nil
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
    (movement.description || "") == value
  end

  defp condition_matches?(%{field: :description, comparator: :regex, value: value}, movement) do
    case Regex.compile(value) do
      {:ok, regex} -> Regex.match?(regex, movement.description || "")
      {:error, _} -> false
    end
  end

  defp condition_matches?(%{field: :amount, comparator: :equals, value: value}, movement) do
    case parse_integer(value) do
      nil -> false
      parsed -> movement.amount == parsed
    end
  end

  defp condition_matches?(%{field: :amount, comparator: :greater_than, value: value}, movement) do
    case parse_integer(value) do
      nil -> false
      parsed -> movement.amount > parsed
    end
  end

  defp condition_matches?(%{field: :amount, comparator: :less_than, value: value}, movement) do
    case parse_integer(value) do
      nil -> false
      parsed -> movement.amount < parsed
    end
  end

  defp condition_matches?(%{field: :on_date, comparator: :equals, value: value}, movement) do
    case parse_date(value) do
      nil -> false
      parsed -> movement.on_date == parsed
    end
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
