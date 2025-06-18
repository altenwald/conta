defmodule Automator.LuaTest do
  use ExUnit.Case
  alias Conta.Automator.Lua

  test "running simple lua code" do
    assert {:ok, 42} = Lua.run("return 42", [])
    assert {:ok, "Mijo!"} = Lua.run("return 'Mijo!'", [])

    params = [{"name", "Manuel"}]
    assert {:ok, "Hello Manuel"} = Lua.run("return 'Hello ' .. name", params)
  end

  test "returning tables" do
    code = """
    data = {}
    data[key] = value
    return data
    """
    params = [{"key", "secret of life"}, {"value", 42}]
    assert {:ok, %{"secret of life" => 42}} = Lua.run(code, params)
  end

  test "returning arrays" do
    code = """
    function fib(n)
      result = {}
      a, b = 0, 1

      for i = 1, n do
        a, b = b, a + b
        table.insert(result, a)
      end
      return result
    end

    return fib(x)
    """
    params = [{"x", 10}]
    assert {:ok, [1, 1, 2, 3, 5, 8, 13, 21, 34, 55]} = Lua.run(code, params)
  end
end
