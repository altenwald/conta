defmodule Conta.AutomatorContextTest do
  use Conta.DataCase
  import Conta.AutomatorFixtures

  alias Conta.Automator
  alias Conta.Projector.Automator.Shortcut
  alias Conta.Projector.Automator.Param

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
    end

    test "get_set_shortcut/1 returns nil for unknown id" do
      assert nil == Automator.get_set_shortcut(Ecto.UUID.generate())
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

    test "sample_limit survives Jason encoding of a Param (API detail response allowlist)" do
      param = %Param{name: "expenses", type: :table, sample_limit: 7}

      assert %{"sample_limit" => 7} = Jason.decode!(Jason.encode!(param))
    end
  end

  describe "new_set_filter/0 and new_set_shortcut/0" do
    test "new_set_filter/0 defaults automator and language" do
      set_filter = Automator.new_set_filter()
      assert set_filter.automator == "automator"
      assert set_filter.language == :lua
      assert set_filter.params == []
    end

    test "new_set_shortcut/0 defaults automator and language" do
      set_shortcut = Automator.new_set_shortcut()
      assert set_shortcut.automator == "automator"
      assert set_shortcut.language == :lua
      assert set_shortcut.params == []
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
end
