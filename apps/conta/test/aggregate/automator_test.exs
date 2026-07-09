defmodule Aggregate.AutomatorTest do
  use ExUnit.Case

  alias Conta.Aggregate.Automator
  alias Conta.Command.SetFilter
  alias Conta.Command.SetShortcut
  alias Conta.Event.FilterSet
  alias Conta.Event.ShortcutSet

  describe "shortcut" do
    test "create successfully" do
      automator = %Automator{}

      command = %SetShortcut{
        automator: "automator",
        name: "credit cash",
        code: "-- something in Lua",
        language: "lua"
      }

      event = Automator.execute(automator, command)

      assert %ShortcutSet{
               automator: "automator",
               name: "credit cash",
               code: "-- something in Lua",
               language: :lua
             } == event

      assert %Automator{
               shortcuts: MapSet.new(["credit cash"])
             } == Automator.apply(automator, event)
    end
  end

  describe "filter" do
    test "a table param's sample_limit survives command -> event" do
      automator = %Automator{}

      command = %SetFilter{
        automator: "automator",
        name: "my filter",
        output: :json,
        code: "-- lua",
        params: [%SetFilter.Param{name: "expenses", type: :table, sample_limit: 10}]
      }

      assert %FilterSet{params: [%FilterSet.Param{name: "expenses", type: :table, sample_limit: 10}]} =
               Automator.execute(automator, command)
    end
  end
end
