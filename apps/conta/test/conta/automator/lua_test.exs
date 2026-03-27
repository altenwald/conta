defmodule Conta.Automator.LuaTest do
  use ExUnit.Case, async: true
  alias Conta.Automator.Lua

  describe "run/2" do
    test "executes simple lua correctly" do
      assert {:ok, 30.0} = Lua.run("return a + b", %{"a" => 10.0, "b" => 20.0})
    end

    test "handles strings correctly" do
      script = """
      return "Hello, " .. name
      """

      assert {:ok, "Hello, world"} = Lua.run(script, %{"name" => "world"})
    end

    test "returns nil correctly when nothing is returned" do
      assert {:ok, nil} = Lua.run("a = 1", %{})
    end

    test "handles syntax errors" do
      {:error, msg} = Lua.run("return a + ", %{})
      assert msg =~ "error"
    end

    test "handles runtime errors gracefully" do
      {:error, msg} = Lua.run("return a + b", %{})
      assert msg =~ "error"
      assert msg =~ "badarith"
    end

    test "processes nested structures" do
      assert {:ok, %{"x" => 1, "y" => 2}} = Lua.run("return {x = 1, y = 2}", %{})
    end
  end
end
