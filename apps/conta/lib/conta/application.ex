defmodule Conta.Application do
  @moduledoc false
  use Application

  def start(_type, _params) do
    children = [
      Conta.Commanded.Application,
      Conta.Repo,
      {DNSCluster, query: Application.get_env(:conta, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Conta.PubSub},

      # Start the Finch HTTP client for sending emails
      {Finch, name: Swoosh.Finch},

      # Start the projectors
      Conta.Projector.Ledger,
      Conta.Projector.Stats,
      Conta.Projector.Book,
      Conta.Projector.Directory
    ]

    options = [strategy: :one_for_one, name: Conta.Supervisor]
    Supervisor.start_link(children, options)
  end
end
