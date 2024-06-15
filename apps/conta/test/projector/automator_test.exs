defmodule Conta.Projector.AutomatorTest do
  use Conta.DataCase
  import Conta.AutomatorFixtures
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
end
