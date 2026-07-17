defmodule ContaWeb.ReconciliationLive.UploadTest do
  use ContaWeb.ConnCase

  import Commanded.Assertions.EventAssertions
  import Phoenix.LiveViewTest
  import Conta.AutomatorFixtures
  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.AccountsFixtures
  alias Conta.Command.SetAccount
  alias Conta.Event.MovementsImported
  alias Conta.Projector.Reconciliation.Movement, as: ReconciliationMovement
  alias Conta.Repo

  setup do
    user = AccountsFixtures.insert(:user) |> AccountsFixtures.confirm_user()

    # Single-segment name on purpose: `SetAccount`'s `valid_parent?/2` requires any
    # parent segment to already exist as an account in the real `Ledger` aggregate
    # (see the identical precedent/rationale in `reconciliation_context_test.exs`'s
    # `confirm_movement/1` setup). A two-segment name like `["Assets", "Bank 1"]`
    # would need `["Assets"]` pre-created too, and risks colliding with whatever
    # other tests set up under that same shared top-level name.
    bank_name = ["Bank #{System.unique_integer([:positive])}"]
    :ok = dispatch(%SetAccount{name: bank_name, type: :assets, currency: :EUR, ledger: "default"})

    importer =
      insert(:importer,
        code: """
        local commands = {}
        for i, row in ipairs(movements) do
          commands[i] = {
            type = "movement",
            data = {
              on_date = row.date,
              description = row.description,
              -- tonumber(row.amount) can come back as a float; `amount` is an
              -- :integer field, so it must be floored/cast here.
              amount = math.floor(tonumber(row.amount) * 100),
              currency = "EUR"
            }
          }
        end
        return {status = "ok", commands = commands}
        """
      )

    :ok = dispatch(Conta.Automator.get_set_importer(importer))

    %{user: user, bank_name: bank_name, importer: importer}
  end

  test "uploads a CSV, runs the importer and shows the imported movements", %{
    conn: conn,
    user: user,
    bank_name: bank_name,
    importer: importer
  } do
    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/ledger/reconciliation/upload")

    csv = "date,description,amount\n2026-07-01,NETFLIX,-13.99\n"

    file =
      file_input(view, "#upload-form", :statement, [
        %{name: "statement.csv", content: csv, type: "text/csv"}
      ])

    render_upload(file, "statement.csv")

    html =
      view
      |> form("#upload-form", %{
        "importer_name" => importer.name,
        "asset_account_name" => Enum.join(bank_name, ".")
      })
      |> render_submit()

    wait_for_event(Conta.Commanded.Application, MovementsImported)

    assert html =~ "Imported 1 movements"

    # `wait_for_event/2` only proves this test's own ad-hoc event-store subscription
    # saw the event, not that the separate `Conta.Projector.Reconciliation`
    # `Commanded.Event.Handler` subscription has finished writing the projection to
    # Postgres (see the identical rationale in `automator_context_test.exs`'s
    # `run_importer/3` test and `reconciliation_context_test.exs`'s `confirm_movement/1`
    # setup). Without waiting for it here too, this test's sandboxed DB connection can
    # tear down before that async write lands, which crashes the projector's connection
    # and — because the sandbox is shared across the whole test run — takes down every
    # other test's DB access for the remainder of the suite.
    assert eventually(fn -> Repo.get_by(ReconciliationMovement, asset_account_name: bank_name) end)
  end

  test "shows an error when no file is chosen on submit", %{
    conn: conn,
    user: user,
    bank_name: bank_name,
    importer: importer
  } do
    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/ledger/reconciliation/upload")

    html =
      view
      |> form("#upload-form", %{
        "importer_name" => importer.name,
        "asset_account_name" => Enum.join(bank_name, ".")
      })
      |> render_submit()

    assert html =~ "Please choose a file to upload"
  end

  # A truly empty (0-byte) upload can't be driven through `render_upload/2`:
  # `Phoenix.LiveViewTest.UploadClient.progress_stats/2` (phoenix_live_view
  # 1.1.27) computes `trunc(new_start / entry.size * 100)`, which divides by
  # zero and raises `ArithmeticError` whenever `entry.size` is 0, regardless
  # of the `percent` argument passed to `render_upload/3`. So this asserts
  # the `{:error, :empty_file} -> ...` clause's message directly against the
  # same `error_message/1` function `handle_event("save", ...)` calls, which
  # is the only reachable way to exercise that specific branch until that
  # library bug is fixed.
  test "maps the empty-file error to the expected message" do
    assert ContaWeb.ReconciliationLive.Upload.error_message({:error, :empty_file}) ==
             "The uploaded file is empty"
  end

  test "maps unrecognized errors to their inspected reason" do
    assert ContaWeb.ReconciliationLive.Upload.error_message({:error, :boom}) == inspect(:boom)
  end

  test "shows an error when a CSV row has a different number of columns than the header", %{
    conn: conn,
    user: user,
    bank_name: bank_name,
    importer: importer
  } do
    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/ledger/reconciliation/upload")

    csv = "date,description,amount\n2026-07-01,NETFLIX\n"

    file =
      file_input(view, "#upload-form", :statement, [
        %{name: "statement.csv", content: csv, type: "text/csv"}
      ])

    render_upload(file, "statement.csv")

    html =
      view
      |> form("#upload-form", %{
        "importer_name" => importer.name,
        "asset_account_name" => Enum.join(bank_name, ".")
      })
      |> render_submit()

    assert html =~ "Row 2 has a different number of columns than the header"
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
