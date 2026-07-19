defmodule Conta.Commanded.RouterTest do
  use Conta.DataCase

  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Command.ImportMovements
  alias Conta.Command.SetAccount
  alias Conta.Commanded.Application, as: CommandedApp

  # Ledger and Reconciliation are both singletons whose commands default their
  # identity field to "default". Without a distinct `prefix:` in `identify/2`,
  # Commanded uses that raw identity as the event store's stream_uuid, so both
  # aggregates would read and write the exact same physical stream and replay
  # each other's events on every rehydration. Only Reconciliation got a
  # prefix (moving it to its own "reconciliation-default" stream) - Ledger
  # keeps its unprefixed "default" stream so its existing history stays
  # reachable.
  test "Ledger keeps writing to \"default\"; Reconciliation writes to its own prefixed stream" do
    account_name = ["Router test #{System.unique_integer([:positive])}"]
    :ok = dispatch(%SetAccount{name: account_name, type: :assets, currency: :EUR, ledger: "default"})

    :ok =
      dispatch(%ImportMovements{
        reconciliation: "default",
        movements: [
          %ImportMovements.Movement{
            on_date: ~D[2026-07-01],
            description: "router test",
            amount: -100,
            currency: :EUR,
            asset_account_name: account_name
          }
        ]
      })

    ledger_types =
      CommandedApp
      |> Commanded.EventStore.stream_forward("default", 0)
      |> Enum.map(& &1.event_type)

    reconciliation_types =
      CommandedApp
      |> Commanded.EventStore.stream_forward("reconciliation-default", 0)
      |> Enum.map(& &1.event_type)

    assert Enum.any?(ledger_types, &String.contains?(&1, "AccountCreated"))
    refute Enum.any?(ledger_types, &String.contains?(&1, "MovementsImported"))

    assert Enum.any?(reconciliation_types, &String.contains?(&1, "MovementsImported"))
    refute Enum.any?(reconciliation_types, &String.contains?(&1, "AccountCreated"))

    # Let the async projectors' writes land before the test's sandboxed
    # connection tears down (see the identical rationale in
    # upload_test.exs/matches_test.exs).
    assert eventually(fn -> Enum.any?(Conta.Ledger.list_accounts(), &(&1.name == account_name)) end)
    assert eventually(fn -> Enum.any?(Conta.Reconciliation.list_movements(), &(&1.description == "router test")) end)
  end

  defp eventually(fun, attempts \\ 100)

  defp eventually(fun, attempts) when attempts > 1 do
    fun.() ||
      (
        Process.sleep(10)
        eventually(fun, attempts - 1)
      )
  end

  defp eventually(fun, _attempts), do: fun.()
end
