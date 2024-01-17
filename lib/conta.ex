defmodule Conta do
  @moduledoc false
  use Application

  def start(_type, _params) do
    children = [
      Conta.Application,
      Conta.Repo,
      Conta.Projector.Ledger,
      Conta.Projector.Stats
    ]
    options = [strategy: :one_for_one, name: Conta.Supervisor]
    Supervisor.start_link(children, options)
  end
end
