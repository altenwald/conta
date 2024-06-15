defmodule Aggregate.AutomatorTest do
  use ExUnit.Case

  describe "shortcut" do
    test "create successfully" do
      automator = %Conta.Aggregate.Automator{}

      command = %Conta.Command.SetShortcut{
        automator: "default",
        name: "credit cash",
        code: "-- something in Lua",
        language: "lua"
      }

      event = Conta.Aggregate.Automator.execute(automator, command)

      assert %Conta.Event.ShortcutSet{
        automator: "default",
        name: "credit cash",
        code: "-- something in Lua",
        language: :lua
      } == event

      assert %Conta.Aggregate.Automator{
        shortcuts: MapSet.new(["credit cash"])
      } == Conta.Aggregate.Automator.apply(automator, event)
    end
  end
end
