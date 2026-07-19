defmodule Conta.ReconciliationContextTest do
  use Conta.DataCase
  import Commanded.Assertions.EventAssertions
  import Conta.ReconciliationFixtures
  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Reconciliation
  alias Conta.Command.ImportMovements
  alias Conta.Command.MarkMovementTransacted
  alias Conta.Command.SetAccount
  alias Conta.Command.SetMatchRule
  alias Conta.Commanded.Application, as: CommandedApp
  alias Conta.Event.MovementsImported
  alias Conta.Event.TransactionCreated
  alias Conta.Projector.Ledger.Entry, as: LedgerEntry
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

    # Command dispatch in this app defaults to `consistency: :eventual` (see
    # `Conta.Commanded.Router`), so `ReconciliationLive.Matches.Index`
    # subscribes to this broadcast instead of only trusting its initial query
    # after a `push_navigate` from the Form (mirrors
    # `Conta.Projector.Automator`). This confirms the projector actually sends
    # it once the read model row lands.
    test "broadcasts event:match_rule_set after projecting a new match rule" do
      Phoenix.PubSub.subscribe(Conta.PubSub, "event:match_rule_set")

      :ok =
        CommandedApp.dispatch(%SetMatchRule{
          name: "broadcast rule",
          conditions: [%SetMatchRule.Condition{field: :description, comparator: :contains, value: "X"}],
          match_type: :all,
          account_name: ["Expenses", "Misc"]
        })

      assert_receive {:match_rule_set, %MatchRule{name: "broadcast rule"}}, 1500
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

  describe "confirm_movement/1" do
    setup do
      # Single-segment names on purpose: `SetAccount`'s `valid_parent?/2` requires any
      # parent segment (all but the last element of a multi-segment name) to already
      # exist as an account in the real `Ledger` aggregate. A two-segment name like
      # `["Assets", "Bank 1"]` would need `["Assets"]` pre-created too, and since the
      # in-memory event store is shared across the whole test run, a fixed top-level
      # `["Assets"]`/`["Expenses"]` name risks colliding with accounts other tests set
      # up with different attributes. A single-segment, fully unique name sidesteps
      # both problems while still exercising a real `assets` account and a real
      # counterpart account in the aggregate.
      bank_name = ["Bank #{System.unique_integer([:positive])}"]
      expense_name = ["Misc #{System.unique_integer([:positive])}"]

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

      # `wait_for_event/3` returns the `%Commanded.EventStore.RecordedEvent{}` itself
      # (not just `:ok`), so we read the aggregate-generated movement `id` straight off
      # the event's data instead of guessing it — and filter the predicate on
      # `asset_account_name == bank_name` (unique per test via `System.unique_integer/1`
      # above), not on `description == "test movement"` like every other test in this
      # describe block also uses: a description-only predicate would happily match a
      # *different* test's `MovementsImported` event from earlier in this same test
      # run (the in-memory event store is process-wide and never reset), which is
      # exactly the `Ecto.NoResultsError` this used to produce intermittently.
      event =
        wait_for_event(Conta.Commanded.Application, MovementsImported, fn event ->
          Enum.any?(event.movements, &(&1.asset_account_name == bank_name))
        end)

      %{id: movement_id} = Enum.find(event.data.movements, &(&1.asset_account_name == bank_name))

      # Beyond the event being appended to the store, `confirm_movement/1` and this
      # test's own assertions read `Conta.Projector.Reconciliation`'s Postgres-backed
      # read model directly. That projector is a separate, independently scheduled
      # `Commanded.Event.Handler` process — `wait_for_event/2,3` only proves *this
      # test's own* ad-hoc event-store subscription received the event, not that the
      # projector's process has finished its `Ecto.Multi` write yet. Dispatching with
      # `consistency: :strong` would normally close that gap, but it's a no-op in this
      # app: `Conta.Projector` (apps/conta/lib/conta/projector.ex:25) strips the
      # `:consistency` option before it reaches `Commanded.Event.Handler`, so every
      # projector is always registered `:eventual` regardless of the `config :conta,
      # consistency: :strong` test setting — a pre-existing gap in shared production
      # code, out of scope for this task. Polling the read model directly is the only
      # reliable way, from here, to know the projection has actually caught up.
      movement = eventually(fn -> Repo.get(Movement, movement_id) end)

      %{movement: movement, bank_name: bank_name, expense_name: expense_name}
    end

    test "confirms a movement with a valid account and creates the transaction", %{
      movement: movement,
      expense_name: expense_name
    } do
      :ok = Reconciliation.update_movement(movement.id, %{"account_name" => expense_name})
      eventually(fn -> Repo.get(Movement, movement.id).account_name == expense_name end)

      assert {:ok, %{movement_id: confirmed_id}} = Reconciliation.confirm_movement(movement.id)
      assert confirmed_id == movement.id

      wait_for_event(Conta.Commanded.Application, TransactionCreated)
      eventually(fn -> is_nil(Repo.get(Movement, movement.id)) end)

      refute Repo.get(Movement, movement.id)
    end

    test "leaves the movement pending when the counterpart account doesn't exist", %{movement: movement} do
      bad_account_name = ["Expenses", "Does Not Exist #{System.unique_integer([:positive])}"]
      :ok = Reconciliation.update_movement(movement.id, %{"account_name" => bad_account_name})
      eventually(fn -> Repo.get(Movement, movement.id).account_name == bad_account_name end)

      assert {:error, _reason} = Reconciliation.confirm_movement(movement.id)

      assert Repo.get(Movement, movement.id)
      refute Repo.get(Movement, movement.id).transacted
    end

    test "confirming a movement without an assigned account returns an error and doesn't touch it", %{
      movement: movement
    } do
      assert {:error, :no_account_assigned} = Reconciliation.confirm_movement(movement.id)
      assert Repo.get(Movement, movement.id)
    end

    test "confirming a zero-amount movement returns an error and doesn't touch it", %{
      movement: movement,
      expense_name: expense_name
    } do
      :ok = Reconciliation.update_movement(movement.id, %{"account_name" => expense_name, "amount" => 0})

      eventually(fn ->
        movement = Repo.get(Movement, movement.id)
        movement.account_name == expense_name and movement.amount == 0
      end)

      assert {:error, :zero_amount} = Reconciliation.confirm_movement(movement.id)

      refute Repo.get(Movement, movement.id).transacted
    end

    test "retrying confirm_movement/1 on an already-transacted movement only retires it, without dispatching SetAccountTransaction again",
         %{movement: movement, expense_name: expense_name} do
      # Reproduces the exact end-state the `%Movement{transacted: true}` clause exists
      # to guard: a *previous* `confirm_movement/1` call already dispatched
      # `SetAccountTransaction` (creating the real ledger transaction) and
      # `MarkMovementTransacted`, but crashed or errored before reaching
      # `RemoveMovement` — leaving the movement `transacted: true` yet still present
      # in the read model, with `account_name` set (in real production, a movement can
      # only reach `transacted: true` via `do_confirm_movement/1`'s general clause,
      # which already requires `account_name` to be non-nil — the `account_name: nil`
      # guard clause runs first). We reproduce that end-state directly, by first
      # assigning `account_name` via `update_movement/2` (matching the sibling
      # "confirms a movement..." test above) and only then dispatching
      # `MarkMovementTransacted` — without ever dispatching `SetAccountTransaction` —
      # so the movement looks exactly like a real interrupted confirmation: transacted,
      # with a real counterpart account, amount unchanged. Skipping the `update_movement/2`
      # step here would leave `account_name: nil`, so removing the `transacted: true`
      # clause would make `do_confirm_movement/1` hit the `account_name: nil` guard
      # clause instead of the general clause — an early exit that produces no
      # `TransactionCreated` at all, making the `refute_receive_event/4` below pass for
      # the wrong reason instead of actually detecting a duplicate dispatch.
      #
      # This test proves — via `refute_receive_event/4`, not just by checking the end
      # state looks right — that retrying `confirm_movement/1` does NOT dispatch a
      # second `SetAccountTransaction` (no `TransactionCreated` is produced for this
      # movement's accounts). If the `transacted: true` clause were ever accidentally
      # reordered after the general clause, this test would fail because a real
      # `TransactionCreated` (a duplicate transaction) would show up during the
      # `refute_receive_event/4` window.
      :ok = Reconciliation.update_movement(movement.id, %{"account_name" => expense_name})
      eventually(fn -> Repo.get(Movement, movement.id).account_name == expense_name end)

      :ok = dispatch(%MarkMovementTransacted{id: movement.id})
      eventually(fn -> Repo.get(Movement, movement.id).transacted end)

      refute_receive_event(
        Conta.Commanded.Application,
        TransactionCreated,
        fn ->
          assert {:ok, %{movement_id: confirmed_id}} = Reconciliation.confirm_movement(movement.id)
          assert confirmed_id == movement.id
        end,
        predicate: fn event -> Enum.any?(event.entries, &(&1.account_name == movement.asset_account_name)) end
      )

      eventually(fn -> is_nil(Repo.get(Movement, movement.id)) end)
      refute Repo.get(Movement, movement.id)
    end
  end

  describe "confirm_movements/1" do
    setup do
      # Single-segment `bank_name`/`good_account` names, for the same
      # `valid_parent?/2` reason documented in the `confirm_movement/1` describe
      # block's `setup` above (a two-segment name like `["Expenses", "Good 1"]`
      # would need `["Expenses"]` pre-created as a real account first).
      bank_name = ["Bank #{System.unique_integer([:positive])}"]
      good_account = ["Good #{System.unique_integer([:positive])}"]

      :ok = dispatch(%SetAccount{name: bank_name, type: :assets, currency: :EUR, ledger: "default"})
      :ok = dispatch(%SetAccount{name: good_account, type: :expenses, currency: :EUR, ledger: "default"})

      :ok =
        dispatch(%ImportMovements{
          movements: [
            %ImportMovements.Movement{
              on_date: ~D[2026-07-01],
              description: "ok one",
              amount: -100,
              currency: :EUR,
              asset_account_name: bank_name
            },
            %ImportMovements.Movement{
              on_date: ~D[2026-07-01],
              description: "bad one",
              amount: -100,
              currency: :EUR,
              asset_account_name: bank_name
            }
          ]
        })

      # As in the `confirm_movement/1` setup above, filter on `asset_account_name`
      # (unique per test) rather than `description` alone, and read the movement
      # ids straight off the matched event's own data instead of doing a
      # description-based `Repo.get_by!/2` lookup afterwards — that would risk
      # matching a same-description row from a different test against the
      # process-wide, never-reset in-memory event store / read model.
      event =
        wait_for_event(Conta.Commanded.Application, MovementsImported, fn event ->
          Enum.any?(event.movements, &(&1.asset_account_name == bank_name))
        end)

      %{id: good_id} = Enum.find(event.data.movements, &(&1.description == "ok one"))
      %{id: bad_id} = Enum.find(event.data.movements, &(&1.description == "bad one"))

      good = eventually(fn -> Repo.get(Movement, good_id) end)
      bad = eventually(fn -> Repo.get(Movement, bad_id) end)

      bad_account_name = ["Expenses", "Nonexistent #{System.unique_integer([:positive])}"]

      :ok = Reconciliation.update_movement(good.id, %{"account_name" => good_account})
      :ok = Reconciliation.update_movement(bad.id, %{"account_name" => bad_account_name})

      eventually(fn ->
        Repo.get(Movement, good.id).account_name == good_account and
          Repo.get(Movement, bad.id).account_name == bad_account_name
      end)

      %{good: good, bad: bad, good_account: good_account}
    end

    test "processes each movement independently and reports per-movement result", %{good: good, bad: bad} do
      results = Reconciliation.confirm_movements([good.id, bad.id])

      assert {:ok, %{movement_id: _}} = results[good.id]
      assert {:error, _reason} = results[bad.id]

      # `confirm_movement/1`'s success path dispatches `RemoveMovement` and returns
      # before the projector (a separate, eventually-consistent process — see the
      # `confirm_movement/1` describe block's `setup` comment above) has necessarily
      # applied it to the read model yet, so poll instead of asserting immediately.
      eventually(fn -> is_nil(Repo.get(Movement, good.id)) end)

      refute Repo.get(Movement, good.id)
      assert Repo.get(Movement, bad.id)
    end

    test "a stale/nonexistent id in the batch doesn't crash the batch or block the other rows", %{
      good: good,
      bad: bad
    } do
      bogus_id = Ecto.UUID.generate()

      results = Reconciliation.confirm_movements([good.id, bogus_id, bad.id])

      assert {:ok, %{movement_id: _}} = results[good.id]
      assert {:error, :not_found} = results[bogus_id]
      assert {:error, _reason} = results[bad.id]

      eventually(fn -> is_nil(Repo.get(Movement, good.id)) end)

      refute Repo.get(Movement, good.id)
      assert Repo.get(Movement, bad.id)
    end

    test "a repeated id in the batch is confirmed exactly once, not double-dispatched", %{
      good: good,
      good_account: good_account
    } do
      results = Reconciliation.confirm_movements([good.id, good.id])

      assert map_size(results) == 1
      assert {:ok, %{movement_id: confirmed_id}} = results[good.id]
      assert confirmed_id == good.id

      eventually(fn -> is_nil(Repo.get(Movement, good.id)) end)
      refute Repo.get(Movement, good.id)

      # Prove this isn't just a coincidentally-clean result map: if the repeated
      # id had slipped past `Enum.uniq/1` and re-entered `confirm_movement/1` a
      # second time, it would have dispatched a second `SetAccountTransaction`,
      # which would show up here as a second ledger entry on the counterpart
      # account (one entry per transaction side, per real transaction).
      entries =
        eventually(fn ->
          case Repo.all(from(e in LedgerEntry, where: e.account_name == ^good_account)) do
            [] -> nil
            entries -> entries
          end
        end)

      assert length(entries) == 1
    end
  end

  # Bounded poll for asynchronous read-model consistency — see the long comment in
  # the `confirm_movement/1` describe block's `setup` above for why this is needed
  # instead of relying solely on `wait_for_event/2,3`/`assert_receive_event/3,4`.
  # Retries every 10ms for up to 1s; the final attempt's result (or `nil`/`false`) is
  # returned as-is so callers get a normal assertion failure with real values instead
  # of an opaque timeout error.
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
