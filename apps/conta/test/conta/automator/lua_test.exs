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

    test "returns ok with nil when nil is explicitly returned" do
      assert {:ok, nil} = Lua.run("return nil", %{})
    end

    test "reports an error when nothing is returned" do
      assert {:error, msg} = Lua.run("a = 1", %{})
      assert msg =~ "return"
    end

    test "handles syntax errors" do
      {:error, msg} = Lua.run("return a + ", %{})
      assert msg =~ "error"
    end

    test "handles runtime errors gracefully" do
      {:error, msg} = Lua.run("return a + b", %{})
      assert msg =~ "bad arithmetic"
    end

    test "processes nested structures" do
      assert {:ok, %{"x" => 1, "y" => 2}} = Lua.run("return {x = 1, y = 2}", %{})
    end
  end
end
