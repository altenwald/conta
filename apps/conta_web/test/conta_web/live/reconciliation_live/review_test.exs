defmodule ContaWeb.ReconciliationLive.ReviewTest do
  use ContaWeb.ConnCase

  import Commanded.Assertions.EventAssertions
  import Phoenix.LiveViewTest
  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.AccountsFixtures
  alias Conta.Command.ImportMovements
  alias Conta.Command.MarkMovementTransacted
  alias Conta.Command.SetAccount
  alias Conta.Event.MovementsImported
  alias Conta.Event.TransactionCreated
  alias Conta.Projector.Reconciliation.Movement
  alias Conta.Reconciliation
  alias Conta.Repo

  setup do
    user = AccountsFixtures.insert(:user) |> AccountsFixtures.confirm_user()
    %{user: user}
  end

  describe "Review" do
    test "movements with and without an account appear in their respective blocks with checkboxes",
         %{conn: conn, user: user} do
      expense = create_expense_account()
      with_account = import_movement() |> assign_account(expense)
      without_account = import_movement()

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/ledger/reconciliation")

      assert has_element?(view, "#movement-#{with_account.id} input[type=checkbox]")
      assert has_element?(view, "#movement-#{without_account.id} input[type=checkbox]")
    end

    test "assigning an account to a bottom-block movement moves it to the top block after the next render",
         %{conn: conn, user: user} do
      movement = import_movement()
      expense = create_expense_account()

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/ledger/reconciliation")

      view
      |> form("#account-form-#{movement.id}", %{"value" => Enum.join(expense, ".")})
      |> render_change()

      assert has_element?(view, "#movement-#{movement.id} input[type=checkbox]")
      assert eventually(fn -> Repo.get(Movement, movement.id).account_name == expense end)
    end

    test "selecting checkboxes and confirming invokes confirm_movements/1: successful rows disappear, failed rows stay with a visible error",
         %{conn: conn, user: user} do
      good_expense = create_expense_account()
      good = import_movement() |> assign_account(good_expense)

      bad_account = ["Expenses", "Nonexistent #{System.unique_integer([:positive])}"]
      bad = import_movement() |> assign_account(bad_account)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/ledger/reconciliation")

      view |> element("#movement-#{good.id} input[type=checkbox]") |> render_click()
      view |> element("#movement-#{bad.id} input[type=checkbox]") |> render_click()

      html = view |> element("button", "Confirm") |> render_click()

      refute has_element?(view, "#movement-#{good.id}")
      assert has_element?(view, "#movement-#{bad.id}")
      assert html =~ "movement-#{bad.id}"

      # The row itself must carry a visible error message, not just any text on the page.
      assert has_element?(view, "#movement-#{bad.id} p.text-error")

      # Let the async projector's delete land before the test's sandboxed connection
      # tears down (see the identical rationale in upload_test.exs/matches_test.exs).
      assert eventually(fn -> is_nil(Repo.get(Movement, good.id)) end)
      assert Repo.get(Movement, bad.id)
    end

    test "a movement with transacted: true shows no checkbox and no inline editing, and its Delete button retries only confirm_movement/1 (no duplicate transaction)",
         %{conn: conn, user: user} do
      expense = create_expense_account()
      movement = import_movement() |> assign_account(expense)

      :ok = dispatch(%MarkMovementTransacted{id: movement.id})
      transacted = eventually(fn -> transacted_movement(movement.id) end)
      assert transacted

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/ledger/reconciliation")

      refute has_element?(view, "#movement-#{movement.id} input[type=checkbox]")
      refute has_element?(view, "#account-form-#{movement.id}")
      refute has_element?(view, "#description-form-#{movement.id}")
      assert has_element?(view, "#movement-#{movement.id} button", "Retry cleanup")
      refute has_element?(view, "#movement-#{movement.id} button", "Delete")

      # A retry of `confirm_movement/1` on an already-transacted movement only retries
      # `RemoveMovement` (Task 15's `do_confirm_movement/1` transacted-true clause) — it
      # must never dispatch `SetAccountTransaction` again. This mirrors the exact proof
      # technique `reconciliation_context_test.exs` uses for the same guarantee at the
      # context-module level.
      refute_receive_event(
        Conta.Commanded.Application,
        TransactionCreated,
        fn ->
          view |> element("#movement-#{movement.id} button", "Retry cleanup") |> render_click()
        end,
        predicate: fn event -> Enum.any?(event.entries, &(&1.account_name == movement.asset_account_name)) end
      )

      assert eventually(fn -> is_nil(Repo.get(Movement, movement.id)) end)
    end

    test "deleting a normal (non-transacted) row with an account assigned dispatches RemoveMovement directly, without creating a transaction",
         %{conn: conn, user: user} do
      expense = create_expense_account()
      movement = import_movement() |> assign_account(expense)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/ledger/reconciliation")

      assert has_element?(view, "#movement-#{movement.id} button", "Delete")
      refute has_element?(view, "#movement-#{movement.id} button", "Retry cleanup")

      # If "Delete" on a normal row ever routed through `Reconciliation.confirm_movement/1`
      # instead of a raw `RemoveMovement` dispatch, this movement (transacted: false, with
      # a valid account already assigned) would have a *real* transaction created as a
      # side effect of clicking "Delete" — exactly the bug this proves does not happen.
      refute_receive_event(
        Conta.Commanded.Application,
        TransactionCreated,
        fn ->
          view |> element("#movement-#{movement.id} button", "Delete") |> render_click()
        end,
        predicate: fn event -> Enum.any?(event.entries, &(&1.account_name == movement.asset_account_name)) end
      )

      assert eventually(fn -> is_nil(Repo.get(Movement, movement.id)) end)
      refute has_element?(view, "#movement-#{movement.id}")
    end

    test "deleting a bottom-block movement (no account assigned) removes it", %{conn: conn, user: user} do
      movement = import_movement()

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/ledger/reconciliation")

      view |> element("#movement-#{movement.id} button", "Delete") |> render_click()

      assert eventually(fn -> is_nil(Repo.get(Movement, movement.id)) end)
      refute has_element?(view, "#movement-#{movement.id}")
    end

    test "select all selects every checkbox-eligible movement; deselect all clears the selection",
         %{conn: conn, user: user} do
      expense = create_expense_account()
      with_account_a = import_movement() |> assign_account(expense)
      with_account_b = import_movement() |> assign_account(expense)
      without_account = import_movement()

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/ledger/reconciliation")

      html = view |> element("#movements-with-account button", "Select all") |> render_click()
      assert html =~ "2 selected"
      assert view |> element("#movement-#{with_account_a.id} input[type=checkbox]") |> render() =~ "checked"
      assert view |> element("#movement-#{with_account_b.id} input[type=checkbox]") |> render() =~ "checked"
      refute view |> element("#movement-#{without_account.id} input[type=checkbox]") |> render() =~ "checked"

      html = view |> element("#movements-with-account button", "Deselect all") |> render_click()
      assert html =~ "0 selected"
      refute view |> element("#movement-#{with_account_a.id} input[type=checkbox]") |> render() =~ "checked"
    end

    test "invert selection toggles every checkbox-eligible movement", %{conn: conn, user: user} do
      expense = create_expense_account()
      a = import_movement() |> assign_account(expense)
      b = import_movement() |> assign_account(expense)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/ledger/reconciliation")

      view |> element("#movement-#{a.id} input[type=checkbox]") |> render_click()

      html = view |> element("#movements-with-account button", "Invert selection") |> render_click()
      assert html =~ "1 selected"
      refute view |> element("#movement-#{a.id} input[type=checkbox]") |> render() =~ "checked"
      assert view |> element("#movement-#{b.id} input[type=checkbox]") |> render() =~ "checked"
    end

    test "batch Delete removes every selected movement", %{conn: conn, user: user} do
      expense = create_expense_account()
      a = import_movement() |> assign_account(expense)
      b = import_movement() |> assign_account(expense)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/ledger/reconciliation")

      view |> element("#movements-with-account button", "Select all") |> render_click()
      view |> element("#movements-with-account button[phx-click=remove_selected]") |> render_click()

      refute has_element?(view, "#movement-#{a.id}")
      refute has_element?(view, "#movement-#{b.id}")

      assert eventually(fn -> is_nil(Repo.get(Movement, a.id)) end)
      assert eventually(fn -> is_nil(Repo.get(Movement, b.id)) end)
    end

    test "select all, deselect all, invert selection, and batch delete in the movements without account block",
         %{conn: conn, user: user} do
      unassigned_a = import_movement()
      unassigned_b = import_movement()
      expense = create_expense_account()
      assigned = import_movement() |> assign_account(expense)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/ledger/reconciliation")

      # Select all in without-account block selects both unassigned movements but NOT the assigned one
      html = view |> element("#movements-without-account button", "Select all") |> render_click()
      assert html =~ "2 selected"
      assert view |> element("#movement-#{unassigned_a.id} input[type=checkbox]") |> render() =~ "checked"
      assert view |> element("#movement-#{unassigned_b.id} input[type=checkbox]") |> render() =~ "checked"
      refute view |> element("#movement-#{assigned.id} input[type=checkbox]") |> render() =~ "checked"

      # Invert selection in without-account block unchecks both
      view |> element("#movements-without-account button", "Invert selection") |> render_click()
      refute view |> element("#movement-#{unassigned_a.id} input[type=checkbox]") |> render() =~ "checked"
      refute view |> element("#movement-#{unassigned_b.id} input[type=checkbox]") |> render() =~ "checked"

      # Select single item and batch delete in without-account block
      view |> element("#movement-#{unassigned_a.id} input[type=checkbox]") |> render_click()
      view |> element("#movements-without-account button[phx-click=remove_selected]") |> render_click()

      refute has_element?(view, "#movement-#{unassigned_a.id}")
      assert has_element?(view, "#movement-#{unassigned_b.id}")
      assert has_element?(view, "#movement-#{assigned.id}")

      assert eventually(fn -> is_nil(Repo.get(Movement, unassigned_a.id)) end)
      assert Repo.get(Movement, unassigned_b.id)
      assert Repo.get(Movement, assigned.id)
    end

    test "editing the description of a normal row dispatches update_movement and reflects the change locally",
         %{conn: conn, user: user} do
      movement = import_movement()

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/ledger/reconciliation")

      view
      |> form("#description-form-#{movement.id}", %{"value" => "corrected description"})
      |> render_change()

      assert view |> element("#description-form-#{movement.id} input") |> render() =~ "corrected description"

      assert eventually(fn -> Repo.get(Movement, movement.id).description == "corrected description" end)
    end

    test "formats movement amount as 2-decimal currency and converts user decimal inputs to integer cents",
         %{conn: conn, user: user} do
      # amount: -1000
      movement = import_movement()

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/ledger/reconciliation")

      assert view |> element("#amount-form-#{movement.id} input") |> render() =~ "value=\"-10.00\""

      view
      |> form("#amount-form-#{movement.id}", %{"value" => "-25.50"})
      |> render_change()

      assert view |> element("#amount-form-#{movement.id} input") |> render() =~ "value=\"-25.50\""
      assert eventually(fn -> Repo.get(Movement, movement.id).amount == -2550 end)
    end

    test "single-row rematch button re-evaluates match rules for that movement", %{conn: conn, user: user} do
      expense = create_expense_account()
      desc = "SPOTIFY_#{System.unique_integer([:positive])}"

      movement = import_movement_with_description(desc)
      assert is_nil(movement.account_name)

      # Create match rule AFTER importing the movement
      :ok =
        dispatch(%Conta.Command.SetMatchRule{
          name: "Spotify Rule",
          conditions: [
            %Conta.Command.SetMatchRule.Condition{field: :description, comparator: :contains, value: desc}
          ],
          match_type: :all,
          account_name: expense,
          concept: "Subscription: Spotify"
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/ledger/reconciliation")

      assert has_element?(view, "#movements-without-account #movement-#{movement.id}")

      view
      |> element("#movement-#{movement.id} button[phx-click=rematch]")
      |> render_click()

      assert eventually(fn ->
               case Repo.get(Movement, movement.id) do
                 %{account_name: ^expense, description: "Subscription: Spotify"} -> true
                 _ -> false
               end
             end)

      assert has_element?(view, "#movements-with-account #movement-#{movement.id}")
    end

    test "batch rematch button in toolbar re-evaluates match rules for selected movements",
         %{conn: conn, user: user} do
      expense = create_expense_account()
      desc = "NETFLIX_#{System.unique_integer([:positive])}"

      m1 = import_movement_with_description(desc)
      m2 = import_movement_with_description(desc)

      assert is_nil(m1.account_name)
      assert is_nil(m2.account_name)

      # Create match rule AFTER importing movements
      :ok =
        dispatch(%Conta.Command.SetMatchRule{
          name: "Netflix Rule",
          conditions: [
            %Conta.Command.SetMatchRule.Condition{field: :description, comparator: :contains, value: desc}
          ],
          match_type: :all,
          account_name: expense,
          concept: "Subscription: Netflix"
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/ledger/reconciliation")

      assert has_element?(view, "#movements-without-account #movement-#{m1.id}")
      assert has_element?(view, "#movements-without-account #movement-#{m2.id}")

      view |> element("#movements-without-account button", "Select all") |> render_click()
      view |> element("#movements-without-account button[phx-click=rematch_selected]") |> render_click()

      assert eventually(fn ->
               Repo.get(Movement, m1.id).account_name == expense and
                 Repo.get(Movement, m2.id).account_name == expense
             end)

      assert has_element?(view, "#movements-with-account #movement-#{m1.id}")
      assert has_element?(view, "#movements-with-account #movement-#{m2.id}")
    end
  end

  defp import_movement_with_description(description) do
    bank_name = ["Bank #{System.unique_integer([:positive])}"]

    :ok = dispatch(%SetAccount{name: bank_name, type: :assets, currency: :EUR, ledger: "default"})

    :ok =
      dispatch(%ImportMovements{
        movements: [
          %ImportMovements.Movement{
            on_date: ~D[2026-07-01],
            description: description,
            amount: -1000,
            currency: :EUR,
            asset_account_name: bank_name
          }
        ]
      })

    event =
      wait_for_event(Conta.Commanded.Application, MovementsImported, fn event ->
        Enum.any?(event.movements, &(&1.asset_account_name == bank_name))
      end)

    %{id: id} = Enum.find(event.data.movements, &(&1.asset_account_name == bank_name))

    eventually(fn -> Repo.get(Movement, id) end)
  end

  defp import_movement do
    bank_name = ["Bank #{System.unique_integer([:positive])}"]
    description = "movement #{System.unique_integer([:positive])}"

    :ok = dispatch(%SetAccount{name: bank_name, type: :assets, currency: :EUR, ledger: "default"})

    :ok =
      dispatch(%ImportMovements{
        movements: [
          %ImportMovements.Movement{
            on_date: ~D[2026-07-01],
            description: description,
            amount: -1000,
            currency: :EUR,
            asset_account_name: bank_name
          }
        ]
      })

    event =
      wait_for_event(Conta.Commanded.Application, MovementsImported, fn event ->
        Enum.any?(event.movements, &(&1.asset_account_name == bank_name))
      end)

    %{id: id} = Enum.find(event.data.movements, &(&1.asset_account_name == bank_name))

    eventually(fn -> Repo.get(Movement, id) end)
  end

  defp create_expense_account do
    name = ["Misc #{System.unique_integer([:positive])}"]
    :ok = dispatch(%SetAccount{name: name, type: :expenses, currency: :EUR, ledger: "default"})
    name
  end

  defp assign_account(movement, account_name) do
    :ok = Reconciliation.update_movement(movement.id, %{"account_name" => account_name})
    eventually(fn -> Repo.get(Movement, movement.id).account_name == account_name end)
    %{movement | account_name: account_name}
  end

  defp transacted_movement(id) do
    case Repo.get(Movement, id) do
      %{transacted: true} = movement -> movement
      _ -> nil
    end
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
