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
    id
    |> get_movement!()
    |> do_confirm_movement()
  end

  def confirm_movements(ids) when is_list(ids) do
    Map.new(ids, fn id -> {id, confirm_movement(id)} end)
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
         # `SetAccountTransaction` a second time — a duplicate transaction. `confirm_movements/1`
         # doesn't introduce this itself: it calls `confirm_movement/1` exactly once per
         # id in a single pass, same as calling it directly, so a batch alone can't
         # trigger the retry. The actual gap is a *human*/UI-level concern — e.g. a user
         # re-clicking "Confirm" on a row stuck after a partial failure, dispatching
         # `confirm_movement/1` or `confirm_movements/1` a second time for the same
         # movement id across separate calls — which is out of scope here and belongs to
         # whichever future task adds that retry affordance. Re-examine then whether this
         # gap needs closing (e.g. via an idempotency check at the `Ledger` aggregate
         # boundary) rather than just documenting it. This is a two-phase-commit across
         # two aggregates with no Process Manager to make it atomic, matching this
         # project's existing conventions — not something to redesign here on its own.
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
