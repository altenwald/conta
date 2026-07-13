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

  def apply(reconciliation, _event), do: reconciliation
end
