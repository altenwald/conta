defmodule Conta.Reconciliation do
  @moduledoc """
  Context for bank-statement reconciliation: listing and looking up
  match rules and pending movements from the read model.
  """

  import Ecto.Query, only: [from: 2]
  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Command.MarkMovementTransacted
  alias Conta.Command.RemoveMovement
  alias Conta.Command.SetAccountTransaction
  alias Conta.Command.SetMatchRule
  alias Conta.Command.UpdateMovement
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

  @doc "Blank `SetMatchRule` command struct for the \"new match rule\" form."
  def new_set_match_rule do
    %SetMatchRule{conditions: []}
  end

  @doc """
  Loads a `SetMatchRule` command struct from an existing read-model row, for the
  "edit match rule" form (and for tests that need to seed the aggregate to match a
  read-model-only fixture, mirroring `Conta.Automator.get_set_shortcut/1`).
  """
  def get_set_match_rule(id) when is_binary(id) do
    id |> get_match_rule!() |> get_set_match_rule()
  end

  def get_set_match_rule(%MatchRule{} = rule) do
    %SetMatchRule{
      id: rule.id,
      name: rule.name,
      conditions:
        for condition <- rule.conditions do
          %SetMatchRule.Condition{
            field: condition.field,
            comparator: condition.comparator,
            value: condition.value,
            value_to: condition.value_to
          }
        end,
      match_type: rule.match_type,
      account_name: rule.account_name
    }
  end

  def list_movements do
    from(m in Movement, order_by: m.on_date)
    |> Repo.all()
  end

  def get_movement!(id) do
    Repo.get!(Movement, id)
  end

  def update_movement(id, changes) when is_map(changes) do
    dispatch(%UpdateMovement{id: id, changes: changes})
  end

  def confirm_movement(id) do
    case Repo.get(Movement, id) do
      nil -> {:error, :not_found}
      movement -> do_confirm_movement(movement)
    end
  end

  # `Enum.uniq/1` collapses repeated ids in the input to a single confirmation
  # attempt. This isn't just an optimization: without it, a duplicate id would
  # call `confirm_movement/1` twice for the same movement within one batch. The
  # first call would confirm and remove it; the second call would then either hit
  # the now-missing row (`{:error, :not_found}`, harmless but misleading) or, if
  # the projector hasn't caught up yet, could re-observe `transacted: false` and
  # re-dispatch `SetAccountTransaction` — a real duplicate financial transaction.
  # Deduplicating here means a repeated id is not a caller error, it's simply
  # processed once.
  def confirm_movements(ids) when is_list(ids) do
    ids
    |> Enum.uniq()
    |> Map.new(fn id -> {id, confirm_movement(id)} end)
  end

  # Paso 0 del algoritmo del spec: si ya está `transacted: true`, un intento anterior
  # ya creó la transacción y solo falló al retirar el movimiento — no se vuelve a
  # construir ni despachar `SetAccountTransaction` (evitaría una transacción
  # duplicada), solo se reintenta la retirada.
  defp do_confirm_movement(%Movement{transacted: true} = movement) do
    retire_movement(movement)
  end

  defp do_confirm_movement(%Movement{account_name: nil}) do
    {:error, :no_account_assigned}
  end

  defp do_confirm_movement(%Movement{amount: 0}) do
    {:error, :zero_amount}
  end

  defp do_confirm_movement(%Movement{} = movement) do
    with {:ok, changeset} <- build_transaction_changeset(movement),
         command = SetAccountTransaction.to_command(changeset),
         :ok <- dispatch(command),
         # Residual risk (documented, accepted): if this `MarkMovementTransacted`
         # dispatch fails *after* `SetAccountTransaction` above already succeeded, the
         # movement's read model never picks up `transacted: true`, so a retry of
         # `confirm_movement/1` would re-enter this clause and dispatch
         # `SetAccountTransaction` a second time — a duplicate transaction.
         # `confirm_movements/1` calls `confirm_movement/1` once per *unique* id
         # (`Enum.uniq/1`'d up front specifically to prevent this), so a single batch
         # call can't trigger it on its own. The actual gap is a *human*/UI-level
         # concern spanning separate calls — e.g. a user re-clicking "Confirm" on a row
         # stuck after a partial failure, dispatching `confirm_movement/1` or
         # `confirm_movements/1` a second time for the same movement id once the first
         # call has already returned — which is out of scope here and belongs to
         # whichever future task adds that retry affordance. Re-examine then whether
         # this gap needs closing (e.g. via an idempotency check at the `Ledger`
         # aggregate boundary) rather than just documenting it. This is a
         # two-phase-commit across two aggregates with no Process Manager to make it
         # atomic, matching this project's existing conventions — not something to
         # redesign here on its own.
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
      %{
        "description" => movement.description,
        "account_name" => movement.asset_account_name,
        "debit" => amount
      },
      %{"description" => movement.description, "account_name" => movement.account_name, "credit" => amount}
    }
  end

  defp entries_for_amount(%Movement{amount: amount} = movement) when amount < 0 do
    {
      %{
        "description" => movement.description,
        "account_name" => movement.asset_account_name,
        "credit" => -amount
      },
      %{"description" => movement.description, "account_name" => movement.account_name, "debit" => -amount}
    }
  end
end
