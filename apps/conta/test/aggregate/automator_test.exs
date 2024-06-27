defmodule Aggregate.AutomatorTest do
  use ExUnit.Case

  alias Conta.Aggregate.Automator
  alias Conta.Command.SetShortcut
  alias Conta.Event.ShortcutSet

  describe "shortcut" do
    test "create successfully" do
      automator = %Automator{}

      command = %SetShortcut{
        automator: "default",
        name: "credit cash",
        code: "-- something in Lua",
        language: "lua"
      }

      event = Automator.execute(automator, command)

      assert %ShortcutSet{
        automator: "default",
        name: "credit cash",
        code: "-- something in Lua",
        language: :lua
      } == event

      assert %Automator{
        shortcuts: MapSet.new(["credit cash"])
      } == Automator.apply(automator, event)
    end
  end
end
