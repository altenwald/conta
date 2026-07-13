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
      changeset =
        MatchRule.changeset(rule, %{
          name: event.name,
          conditions: conditions,
          match_type: event.match_type,
          account_name: event.account_name
        })

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
