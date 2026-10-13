defmodule Conta.RuntimeConfigTest do
  use ExUnit.Case, async: false

  test "the Telegram token is read at release startup" do
    vars = %{
      "DATABASE_URL" => "ecto://test:test@localhost/conta_test",
      "EVENTSOURCE_URL" => "ecto://test:test@localhost/conta_es_test",
      "SECRET_KEY_BASE" => String.duplicate("test", 16),
      "GRANTED_USERS" => "",
      "EXGRAM_TOKEN" => "runtime-only-fixture"
    }

    previous = Map.new(vars, fn {key, _} -> {key, System.get_env(key)} end)
    System.put_env(vars)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)

    config = Config.Reader.read!(Path.expand("../../../../config/runtime.exs", __DIR__), env: :prod)
    assert get_in(config, [:ex_gram, :token]) == "runtime-only-fixture"
  end
end
