defmodule Conta.ProjectorTest do
  use Conta.DataCase

  defmodule StrongProjector do
    use Conta.Projector,
      application: Conta.Commanded.Application,
      repo: Conta.Repo,
      name: __MODULE__,
      consistency: :strong

    project(%Conta.Event.ContactRemoved{}, fn multi -> multi end)
  end

  defmodule EventualProjector do
    use Conta.Projector,
      application: Conta.Commanded.Application,
      repo: Conta.Repo,
      name: __MODULE__,
      consistency: :eventual

    project(%Conta.Event.ContactRemoved{}, fn multi -> multi end)
  end

  describe "consistency option propagation" do
    test "preserves :consistency in handler child_spec options" do
      strong_spec = StrongProjector.child_spec([])
      {_module, opts} = strong_spec.id
      assert Keyword.get(opts, :consistency) == :strong

      eventual_spec = EventualProjector.child_spec([])
      {_module, opts} = eventual_spec.id
      assert Keyword.get(opts, :consistency) == :eventual
    end

    test "registers strong projector in Commanded.Subscriptions when started" do
      # Clean up on exit so test projector does not leave a dangling entry in subscriptions registry
      on_exit(fn ->
        table = Module.concat([Conta.Commanded.Application, Commanded.Subscriptions.Registry])
        :ets.delete(table, inspect(StrongProjector))
      end)

      # Start strong projector
      {:ok, pid} = start_supervised({StrongProjector, []})

      subscriptions = Commanded.Subscriptions.all(Conta.Commanded.Application)
      strong_entry = Enum.find(subscriptions, fn {_name, mod, _pid} -> mod == StrongProjector end)

      assert strong_entry != nil
      {name, mod, registered_pid} = strong_entry
      assert name == inspect(StrongProjector)
      assert mod == StrongProjector
      assert registered_pid == pid
    end

    test "does not register eventual projector in Commanded.Subscriptions" do
      {:ok, _pid} = start_supervised({EventualProjector, []})

      subscriptions = Commanded.Subscriptions.all(Conta.Commanded.Application)
      eventual_entry = Enum.find(subscriptions, fn {_name, mod, _pid} -> mod == EventualProjector end)

      assert eventual_entry == nil
    end

    test "dispatch with consistency: :strong blocks until projection is written to Postgres" do
      account_name = ["Strong Consistency Test #{System.unique_integer([:positive])}"]

      command = %Conta.Command.SetAccount{
        name: account_name,
        type: :assets,
        currency: :EUR,
        ledger: "default"
      }

      assert :ok = Conta.Commanded.Application.dispatch(command, consistency: :strong)

      # Without any sleep or polling, the projection row must already be committed in Postgres
      account = Conta.Repo.get_by(Conta.Projector.Ledger.Account, name: account_name)
      assert account != nil
      assert account.name == account_name
      assert account.type == :assets
    end
  end
end
