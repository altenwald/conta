defmodule Conta.Projector.AutomatorTest do
  use Conta.DataCase
  alias Conta.Projector.Automator

  setup do
    version =
      if pv = Repo.get(Automator.ProjectionVersion, "Conta.Projector.Automator") do
        pv.last_seen_version + 1
      else
        1
      end

    on_exit(fn ->
      Repo.delete_all(Automator.Shortcut)
      Repo.delete_all(Automator.Filter)
      Repo.delete_all(Automator.ProjectionVersion)
    end)

    %{
      handler_name: "Conta.Projector.Automator",
      event_number: version
    }
  end

  describe "shortcut" do
    test "create successfully", metadata do
      event = %Conta.Event.ShortcutSet{
        automator: "default",
        name: "credit cash",
        code: "-- something in Lua",
        language: :lua
      }

      assert :ok = Automator.handle(event, metadata)

      assert %Automator.Shortcut{
               automator: "default",
               name: "credit cash",
               code: "-- something in Lua",
               language: :lua
             } = Repo.get_by!(Automator.Shortcut, name: "credit cash", automator: "default")
    end
  end

  describe "filter" do
    test "persists a table param's sample_limit", metadata do
      event = %Conta.Event.FilterSet{
        automator: "automator",
        name: "expenses report",
        output: :json,
        code: "-- lua",
        params: [%Conta.Event.FilterSet.Param{name: "expenses", type: :table, sample_limit: 10}]
      }

      assert :ok = Automator.handle(event, metadata)

      filter = Repo.get_by!(Automator.Filter, name: "expenses report", automator: "automator")
      assert [%Automator.Param{name: "expenses", type: :table, sample_limit: 10}] = filter.params
    end
  end
end
