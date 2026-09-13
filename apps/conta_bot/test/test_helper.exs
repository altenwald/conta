{:ok, _} = Application.ensure_all_started(:conta)
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Conta.Repo, :manual)
