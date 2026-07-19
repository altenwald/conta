defmodule Conta.AutomatorContextTest do
  use Conta.DataCase
  import Commanded.Assertions.EventAssertions
  import Conta.AutomatorFixtures

  alias Conta.Automator
  alias Conta.Command.SetFilter
  alias Conta.Command.SetImporter
  alias Conta.Command.SetShortcut
  alias Conta.Commanded.Application, as: CommandedApp
  alias Conta.Event.MovementsImported
  alias Conta.Projector.Automator.Importer
  alias Conta.Projector.Automator.Shortcut
  alias Conta.Projector.Automator.Param
  alias Conta.Projector.Reconciliation.Movement, as: ReconciliationMovement

  describe "shortcuts — DB queries" do
    test "list_shortcuts/0 returns all shortcuts for default automator" do
      shortcut = insert(:shortcut)
      result = Automator.list_shortcuts()
      assert Enum.any?(result, &(&1.id == shortcut.id))
    end

    test "get_shortcut/1 by id returns the shortcut" do
      shortcut = insert(:shortcut)
      assert %Shortcut{id: id} = Automator.get_shortcut(shortcut.id)
      assert id == shortcut.id
    end

    test "get_shortcut!/1 by id raises on missing" do
      assert_raise Ecto.NoResultsError, fn ->
        Automator.get_shortcut!(Ecto.UUID.generate())
      end
    end

    test "get_shortcut_by_name/1 returns shortcut by name" do
      shortcut = insert(:shortcut)
      assert %Shortcut{name: name} = Automator.get_shortcut_by_name(shortcut.name)
      assert name == shortcut.name
    end

    test "get_set_shortcut/1 returns SetShortcut command" do
      shortcut = insert(:shortcut)
      set_shortcut = Automator.get_set_shortcut(shortcut.id)
      assert set_shortcut.name == shortcut.name
      assert set_shortcut.code == shortcut.code
      assert set_shortcut.description == shortcut.description
    end

    test "get_set_shortcut/1 returns nil for unknown id" do
      assert nil == Automator.get_set_shortcut(Ecto.UUID.generate())
    end

    test "get_set_shortcut/1 carries sample_limit for a table param" do
      shortcut =
        insert(:shortcut, %{
          params: [%Param{name: "expenses", type: :table, sample_limit: 7}]
        })

      set_shortcut = Automator.get_set_shortcut(shortcut.id)

      assert [%Conta.Command.SetShortcut.Param{name: "expenses", type: :table, sample_limit: 7}] =
               set_shortcut.params
    end

    test "get_remove_shortcut/1 returns RemoveShortcut command from id" do
      shortcut = insert(:shortcut)
      remove = Automator.get_remove_shortcut(shortcut.id)
      assert remove.name == shortcut.name
    end

    test "get_remove_shortcut/1 returns RemoveShortcut from struct" do
      shortcut = insert(:shortcut)
      remove = Automator.get_remove_shortcut(shortcut)
      assert remove.automator == shortcut.automator
    end
  end

  describe "importers — DB queries" do
    test "list_importers/0 returns all importers for default automator" do
      importer = insert(:importer)
      result = Automator.list_importers()
      assert Enum.any?(result, &(&1.id == importer.id))
    end

    test "get_importer/1 by id returns the importer" do
      importer = insert(:importer)
      assert %Importer{id: id} = Automator.get_importer(importer.id)
      assert id == importer.id
    end

    test "get_importer!/1 by id raises on missing" do
      assert_raise Ecto.NoResultsError, fn ->
        Automator.get_importer!(Ecto.UUID.generate())
      end
    end

    test "get_importer_by_name/1 returns importer by name" do
      importer = insert(:importer)
      assert %Importer{name: name} = Automator.get_importer_by_name(importer.name)
      assert name == importer.name
    end

    test "get_set_importer/1 returns SetImporter command" do
      importer = insert(:importer)
      set_importer = Automator.get_set_importer(importer.id)
      assert set_importer.name == importer.name
      assert set_importer.code == importer.code
      assert set_importer.description == importer.description
    end

    test "get_set_importer/1 returns nil for unknown id" do
      assert nil == Automator.get_set_importer(Ecto.UUID.generate())
    end

    test "get_remove_importer/1 returns RemoveImporter command from id" do
      importer = insert(:importer)
      remove = Automator.get_remove_importer(importer.id)
      assert remove.name == importer.name
    end

    test "get_remove_importer/1 returns RemoveImporter from struct" do
      importer = insert(:importer)
      remove = Automator.get_remove_importer(importer)
      assert remove.automator == importer.automator
    end
  end

  describe "new_set_importer/0" do
    test "new_set_importer/0 defaults automator and language" do
      set_importer = Automator.new_set_importer()
      assert set_importer.automator == "automator"
      assert set_importer.language == :lua
    end

    test "new_set_importer/0 seeds the code editor with a movement command skeleton" do
      set_importer = Automator.new_set_importer()
      assert set_importer.code =~ ~S[type = "movement"]
      assert set_importer.code =~ "ipairs(movements)"
    end
  end

  # Command dispatch in this app defaults to `consistency: :eventual` (see
  # `Conta.Commanded.Router`), so a caller cannot rely on the read model being
  # up to date right after `dispatch/1` returns `:ok`. The *Index LiveViews
  # cope with that by subscribing to these broadcasts (mirroring
  # Conta.Projector.Book/Directory) instead of only trusting their initial
  # query - these tests confirm the projector actually sends them once the
  # read model row lands, independently of the LiveView's reaction to them.
  describe "Conta.Projector.Automator broadcasts on set" do
    test "broadcasts event:importer_set after projecting a new importer" do
      Phoenix.PubSub.subscribe(Conta.PubSub, "event:importer_set")

      :ok =
        CommandedApp.dispatch(%SetImporter{
          name: "broadcast importer",
          automator: "automator",
          code: "return {status = \"ok\", commands = {}}"
        })

      assert_receive {:importer_set, %Importer{name: "broadcast importer"}}, 1500
    end

    test "broadcasts event:filter_set after projecting a new filter" do
      Phoenix.PubSub.subscribe(Conta.PubSub, "event:filter_set")

      :ok =
        CommandedApp.dispatch(%SetFilter{
          name: "broadcast filter",
          automator: "automator",
          output: :json,
          code: "return {}"
        })

      assert_receive {:filter_set, %Conta.Projector.Automator.Filter{name: "broadcast filter"}}, 1500
    end

    test "broadcasts event:shortcut_set after projecting a new shortcut" do
      Phoenix.PubSub.subscribe(Conta.PubSub, "event:shortcut_set")

      :ok =
        CommandedApp.dispatch(%SetShortcut{
          name: "broadcast shortcut",
          automator: "automator",
          code: "return {status = \"ok\", commands = {}}"
        })

      assert_receive {:shortcut_set, %Shortcut{name: "broadcast shortcut"}}, 1500
    end
  end

  describe "filters — DB queries" do
    setup do
      filter =
        Repo.insert!(%Conta.Projector.Automator.Filter{
          name: "my_filter",
          automator: "automator",
          code: "-- lua",
          language: :lua,
          output: :json,
          type: :all
        })

      %{filter: filter}
    end

    test "list_filters/0 returns filters", %{filter: filter} do
      result = Automator.list_filters()
      assert Enum.any?(result, &(&1.id == filter.id))
    end

    test "list_filters_by_type/1 returns matching type", %{filter: filter} do
      result = Automator.list_filters_by_type(:invoice)
      # filter.type == :all, so it appears for any type
      assert Enum.any?(result, &(&1.id == filter.id))
    end

    test "get_filter/1 by id returns the filter", %{filter: filter} do
      assert %Conta.Projector.Automator.Filter{} = Automator.get_filter(filter.id)
    end

    test "get_filter!/1 raises on missing" do
      assert_raise Ecto.NoResultsError, fn ->
        Automator.get_filter!(Ecto.UUID.generate())
      end
    end

    test "get_filter_by_name/1 returns filter by name", %{filter: filter} do
      assert %Conta.Projector.Automator.Filter{name: name} = Automator.get_filter_by_name(filter.name)
      assert name == filter.name
    end

    test "get_remove_filter/1 returns RemoveFilter from id", %{filter: filter} do
      remove = Automator.get_remove_filter(filter.id)
      assert remove.name == filter.name
    end

    test "get_set_filter/1 returns nil for unknown id" do
      assert nil == Automator.get_set_filter(Ecto.UUID.generate())
    end

    test "get_set_filter/1 carries description and type for editing" do
      filter =
        Repo.insert!(%Conta.Projector.Automator.Filter{
          name: "invoice_filter",
          automator: "automator",
          code: "-- lua",
          language: :lua,
          output: :json,
          type: :invoice,
          description: "lists paid invoices"
        })

      set_filter = Automator.get_set_filter(filter.id)

      assert set_filter.type == :invoice
      assert set_filter.description == "lists paid invoices"
    end

    test "get_set_filter/1 carries sample_limit for a table param", %{filter: filter} do
      filter =
        filter
        |> Ecto.Changeset.change(
          params: [
            %Conta.Projector.Automator.Param{name: "expenses", type: :table, sample_limit: 7}
          ]
        )
        |> Repo.update!()

      set_filter = Automator.get_set_filter(filter.id)

      assert [%Conta.Command.SetFilter.Param{name: "expenses", type: :table, sample_limit: 7}] =
               set_filter.params
    end
  end

  describe "validate_params/2 — pure logic, no DB nor ES" do
    test "empty shortcut params always passes" do
      shortcut = %Shortcut{params: []}
      assert [] = Automator.cast(shortcut, %{})
    end

    test "validates string param present" do
      # We use cast/2 which is pure
      params = [%Param{name: "amount", type: :string}]
      shortcut = %Shortcut{params: params, code: "", language: :lua}
      result = Automator.cast(shortcut, %{"amount" => "hello"})
      assert [{"amount", "hello"}] = result
    end

    test "validates money param as integer" do
      params = [%Param{name: "amount", type: :money}]
      shortcut = %Shortcut{params: params, code: "", language: :lua}
      result = Automator.cast(shortcut, %{"amount" => 100})
      assert [{"amount", 100}] = result
    end

    test "validates money param as string integer" do
      params = [%Param{name: "amount", type: :money}]
      shortcut = %Shortcut{params: params, code: "", language: :lua}
      result = Automator.cast(shortcut, %{"amount" => "100"})
      assert [{"amount", 100}] = result
    end

    test "validates money param as float" do
      params = [%Param{name: "amount", type: :money}]
      shortcut = %Shortcut{params: params, code: "", language: :lua}
      result = Automator.cast(shortcut, %{"amount" => 1.50})
      assert [{"amount", 150}] = result
    end

    test "cast money param as decimal string (e.g. from a test-data form field)" do
      params = [%Param{name: "amount", type: :money}]
      shortcut = %Shortcut{params: params, code: "", language: :lua}
      result = Automator.cast(shortcut, %{"amount" => "12.50"})
      assert [{"amount", 1250}] = result
    end

    test "cast money param as invalid decimal string returns nil" do
      params = [%Param{name: "amount", type: :money}]
      shortcut = %Shortcut{params: params, code: "", language: :lua}
      result = Automator.cast(shortcut, %{"amount" => "12.50.30"})
      assert [{"amount", nil}] = result
    end

    test "cast returns nil for missing money param" do
      params = [%Param{name: "amount", type: :money}]
      shortcut = %Shortcut{params: params, code: "", language: :lua}
      result = Automator.cast(shortcut, %{})
      assert [{"amount", nil}] = result
    end

    test "cast currency param" do
      params = [%Param{name: "currency", type: :currency}]
      shortcut = %Shortcut{params: params, code: "", language: :lua}
      result = Automator.cast(shortcut, %{"currency" => "EUR"})
      assert [{"currency", :EUR}] = result
    end

    test "cast date param" do
      params = [%Param{name: "date", type: :date}]
      shortcut = %Shortcut{params: params, code: "", language: :lua}
      result = Automator.cast(shortcut, %{"date" => "2024-01-15"})
      assert [{"date", "2024-01-15"}] = result
    end

    test "cast date param with invalid date returns nil" do
      params = [%Param{name: "date", type: :date}]
      shortcut = %Shortcut{params: params, code: "", language: :lua}
      result = Automator.cast(shortcut, %{"date" => "not-a-date"})
      assert [{"date", nil}] = result
    end

    test "cast options param with valid option" do
      params = [%Param{name: "status", type: :options, options: ["active", "inactive"]}]
      shortcut = %Shortcut{params: params, code: "", language: :lua}
      result = Automator.cast(shortcut, %{"status" => "active"})
      assert [{"status", "active"}] = result
    end

    test "cast options param with invalid option returns nil" do
      params = [%Param{name: "status", type: :options, options: ["active", "inactive"]}]
      shortcut = %Shortcut{params: params, code: "", language: :lua}
      result = Automator.cast(shortcut, %{"status" => "unknown"})
      assert [{"status", nil}] = result
    end

    test "cast account_name param splits by dot" do
      params = [%Param{name: "account", type: :account_name}]
      shortcut = %Shortcut{params: params, code: "", language: :lua}
      result = Automator.cast(shortcut, %{"account" => "Assets.Bank"})
      assert [{"account", ["Assets", "Bank"]}] = result
    end

    test "cast account_name param returns nil when missing" do
      params = [%Param{name: "account", type: :account_name}]
      shortcut = %Shortcut{params: params, code: "", language: :lua}
      result = Automator.cast(shortcut, %{})
      assert [{"account", nil}] = result
    end

    test "cast table param with list" do
      params = [%Param{name: "rows", type: :table}]
      shortcut = %Shortcut{params: params, code: "", language: :lua}
      result = Automator.cast(shortcut, %{"rows" => [[1, 2], [3, 4]]})
      assert [{"rows", [[1, 2], [3, 4]]}] = result
    end

    test "cast table param defaults blank string to an empty table" do
      params = [%Param{name: "rows", type: :table}]
      shortcut = %Shortcut{params: params, code: "", language: :lua}
      result = Automator.cast(shortcut, %{"rows" => ""})
      assert [{"rows", []}] = result
    end

    test "cast table param defaults missing value to an empty table" do
      params = [%Param{name: "rows", type: :table}]
      shortcut = %Shortcut{params: params, code: "", language: :lua}
      result = Automator.cast(shortcut, %{})
      assert [{"rows", []}] = result
    end

    test "cast table param decodes a JSON-encoded string (e.g. a form-encoded API call)" do
      params = [%Param{name: "rows", type: :table}]
      shortcut = %Shortcut{params: params, code: "", language: :lua}
      result = Automator.cast(shortcut, %{"rows" => ~S([{"a": 1}, {"a": 2}])})
      assert [{"rows", [[{"a", 1}], [{"a", 2}]]}] = result
    end

    test "cast table param decodes an empty JSON array string to an empty table" do
      params = [%Param{name: "rows", type: :table}]
      shortcut = %Shortcut{params: params, code: "", language: :lua}
      result = Automator.cast(shortcut, %{"rows" => "[]"})
      assert [{"rows", []}] = result
    end

    test "cast table param defaults invalid JSON string to an empty table" do
      params = [%Param{name: "rows", type: :table}]
      shortcut = %Shortcut{params: params, code: "", language: :lua}
      result = Automator.cast(shortcut, %{"rows" => "not json"})
      assert [{"rows", []}] = result
    end

    test "sample_limit survives Jason encoding of a Param (API detail response allowlist)" do
      param = %Param{name: "expenses", type: :table, sample_limit: 7}

      assert %{"sample_limit" => 7} = Jason.decode!(Jason.encode!(param))
    end
  end

  describe "SetFilter.changeset/2 — sample_limit validation" do
    test "rejects a negative sample_limit instead of letting it crash later" do
      changeset =
        Conta.Command.SetFilter.changeset(%Conta.Command.SetFilter{}, %{
          name: "my filter",
          automator: "automator",
          output: "json",
          code: "-- lua",
          params: [%{name: "expenses", type: "table", sample_limit: -1}]
        })

      assert [param_changeset] = changeset.changes.params
      assert %{sample_limit: ["must be greater than 0"]} = errors_on(param_changeset)
    end

    test "rejects a zero sample_limit" do
      changeset =
        Conta.Command.SetFilter.changeset(%Conta.Command.SetFilter{}, %{
          name: "my filter",
          automator: "automator",
          output: "json",
          code: "-- lua",
          params: [%{name: "expenses", type: "table", sample_limit: 0}]
        })

      assert [param_changeset] = changeset.changes.params
      assert %{sample_limit: ["must be greater than 0"]} = errors_on(param_changeset)
    end

    test "accepts a nil/absent sample_limit (no regression for existing table params)" do
      changeset =
        Conta.Command.SetFilter.changeset(%Conta.Command.SetFilter{}, %{
          name: "my filter",
          automator: "automator",
          output: "json",
          code: "-- lua",
          params: [%{name: "expenses", type: "table"}]
        })

      assert changeset.valid?
      assert [%Ecto.Changeset{valid?: true} = param_changeset] = changeset.changes.params
      assert param_changeset.errors == []
    end
  end

  describe "SetShortcut.changeset/2 — sample_limit validation" do
    test "rejects a negative sample_limit instead of letting it crash later" do
      changeset =
        Conta.Command.SetShortcut.changeset(%Conta.Command.SetShortcut{}, %{
          name: "my shortcut",
          automator: "automator",
          code: "-- lua",
          params: [%{name: "expenses", type: "table", sample_limit: -1}]
        })

      assert [param_changeset] = changeset.changes.params
      assert %{sample_limit: ["must be greater than 0"]} = errors_on(param_changeset)
    end

    test "accepts a nil/absent sample_limit (no regression for existing table params)" do
      changeset =
        Conta.Command.SetShortcut.changeset(%Conta.Command.SetShortcut{}, %{
          name: "my shortcut",
          automator: "automator",
          code: "-- lua",
          params: [%{name: "expenses", type: "table"}]
        })

      assert changeset.valid?
      assert [%Ecto.Changeset{valid?: true} = param_changeset] = changeset.changes.params
      assert param_changeset.errors == []
    end
  end

  describe "new_set_filter/0 and new_set_shortcut/0" do
    test "new_set_filter/0 defaults automator and language" do
      set_filter = Automator.new_set_filter()
      assert set_filter.automator == "automator"
      assert set_filter.language == :lua
      assert set_filter.params == []
    end

    test "new_set_filter/0 seeds the code editor with a return-shape skeleton" do
      set_filter = Automator.new_set_filter()
      assert set_filter.code =~ "return {}"
    end

    test "new_set_shortcut/0 defaults automator and language" do
      set_shortcut = Automator.new_set_shortcut()
      assert set_shortcut.automator == "automator"
      assert set_shortcut.language == :lua
      assert set_shortcut.params == []
    end

    test "new_set_shortcut/0 seeds the code editor with a command skeleton" do
      set_shortcut = Automator.new_set_shortcut()
      assert set_shortcut.code =~ ~S[type = "transaction"]
      assert set_shortcut.code =~ ~S[type = "invoice"]
    end
  end

  describe "run_filter/3 — validate_params date check (params are not pre-cast here)" do
    test "rejects a non-ISO8601 date instead of always accepting it" do
      filter = %Conta.Projector.Automator.Filter{
        params: [%Param{name: "date", type: :date}],
        code: "return date",
        language: :lua,
        output: :json
      }

      assert {:error, %{"date" => ["is invalid"]}} =
               Automator.run_filter("automator", filter, %{"date" => "not-a-date"})
    end
  end

  describe "test_run_filter/3" do
    test "runs Lua code against test params and returns the decoded result" do
      params_defs = [
        %Param{name: "a", type: :integer},
        %Param{name: "b", type: :integer}
      ]

      assert {:ok, 30} =
               Automator.test_run_filter(params_defs, "return a + b", %{"a" => "10", "b" => "20"})
    end

    test "returns a validation error when a required param is missing" do
      params_defs = [%Param{name: "a", type: :integer}]

      assert {:error, %{"a" => ["is invalid"]}} =
               Automator.test_run_filter(params_defs, "return a", %{})
    end

    test "returns a Lua error for invalid code" do
      assert {:error, _reason} = Automator.test_run_filter([], "this is not lua", %{})
    end

    test "casts account_name params before validating them" do
      params_defs = [%Param{name: "account", type: :account_name}]

      assert {:ok, ["Assets", "Bank"]} =
               Automator.test_run_filter(params_defs, "return account", %{"account" => "Assets.Bank"})
    end
  end

  describe "run_importer/3" do
    test "dispatches ImportMovements from the Lua script's movement commands" do
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
                -- tonumber(row.amount) can come back as a float (e.g. -100.0);
                -- the `amount` field is an :integer, so it must be floored/cast here.
                amount = math.floor(tonumber(row.amount)),
                currency = "EUR"
              }
            }
          end
          return {status = "ok", commands = commands}
          """
        )

      rows = [%{"date" => "2026-07-01", "description" => "test row", "amount" => "-100"}]

      # Single-segment, uniquely-suffixed account name on purpose: `ImportMovements`
      # dispatch here is a real end-to-end call through the router into the
      # `Reconciliation` aggregate, and its read-model projection runs
      # asynchronously in a different process. Without waiting for the resulting
      # `MovementsImported` event, this test (and the sandboxed DB connection it
      # owns) can finish and tear down before the async `Conta.Projector.Reconciliation`
      # handler gets to persist the projection, which crashes that handler's
      # connection and — because the sandbox is shared across the whole test run —
      # takes down every other test's DB access for the remainder of the suite.
      # A unique account name also keeps the `wait_for_event/3` predicate from
      # matching some other test's leftover event on the process-wide in-memory
      # event store.
      asset_account_name = ["Bank #{System.unique_integer([:positive])}"]

      assert :ok = Automator.run_importer(importer, %{"movements" => rows}, asset_account_name)

      wait_for_event(Conta.Commanded.Application, MovementsImported, fn event ->
        Enum.any?(event.movements, &(&1.asset_account_name == asset_account_name))
      end)

      # As documented at length in `reconciliation_context_test.exs`'s
      # `confirm_movement/1` setup block: `wait_for_event/3` only proves this test's
      # own ad-hoc event-store subscription saw the event, not that the separate
      # `Conta.Projector.Reconciliation` `Commanded.Event.Handler` subscription has
      # finished writing the projection to Postgres. Poll the actual read model too,
      # so this test (and the sandboxed DB connection it owns) can't tear down before
      # that async write lands.
      assert eventually(fn -> Repo.get_by(ReconciliationMovement, asset_account_name: asset_account_name) end)
    end

    test "returns {:error, :importer_not_found} when the importer doesn't exist" do
      assert {:error, :importer_not_found} =
               Automator.run_importer("does-not-exist-#{System.unique_integer([:positive])}", %{}, [])
    end

    test "returns an error when the Lua code doesn't return the expected shape" do
      importer = insert(:importer, code: "return {status = \"error\"}")

      assert {:error, {:invalid_code_return, %{"status" => "error"}}} =
               Automator.run_importer(importer, %{"movements" => []}, ["Bank"])
    end
  end

  describe "test_run_shortcut/3" do
    test "returns the commands the Lua code would generate, without dispatching them" do
      params_defs = [%Param{name: "amount", type: :money}]

      code = ~S"""
      return {status = "ok", commands = {{type = "transaction", data = {foo = "bar"}}}}
      """

      assert {:ok, [%{"type" => "transaction", "data" => %{"foo" => "bar"}}]} =
               Automator.test_run_shortcut(params_defs, code, %{"amount" => "100"})
    end

    test "returns an error when the Lua code doesn't return the expected shape" do
      assert {:error, {:invalid_code_return, 42}} = Automator.test_run_shortcut([], "return 42", %{})
    end
  end

  describe "test_run_importer/2" do
    test "returns the commands the Lua code would generate, without dispatching them" do
      code = ~S"""
      return {status = "ok", commands = {{type = "movement", data = {foo = "bar"}}}}
      """

      assert {:ok, [%{"type" => "movement", "data" => %{"foo" => "bar"}}]} =
               Automator.test_run_importer(code, "[]")
    end

    test "passes the decoded movements table into the Lua script as the fixed `movements` param" do
      code = ~S"""
      local total = 0
      for _, row in ipairs(movements) do
        total = total + row.amount
      end
      return {status = "ok", commands = {{type = "total", data = {total = total}}}}
      """

      assert {:ok, [%{"type" => "total", "data" => %{"total" => 15}}]} =
               Automator.test_run_importer(code, ~S([{"amount": 10}, {"amount": 5}]))
    end

    test "returns an error when the Lua code doesn't return the expected shape" do
      assert {:error, {:invalid_code_return, 42}} = Automator.test_run_importer("return 42", "[]")
    end
  end

  # See the identical helper (and the detailed rationale in `confirm_movement/1`'s
  # setup block) in `reconciliation_context_test.exs`: `wait_for_event/2,3` only
  # proves this test's own ad-hoc event-store subscription saw an event, not that a
  # separate `Commanded.Event.Handler` projector has finished writing to Postgres.
  # Polling the read model directly is the reliable way to know a projection landed.
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
