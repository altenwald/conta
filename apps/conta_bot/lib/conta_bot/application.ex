defmodule ContaBot.Application do
  use Application

  @impl Application
  def start(_start_type, _start_args) do
    children = [
      # Start the Registry for transactions
      {Registry, keys: :unique, name: ContaBot.Action.Transaction.Registry},
      # Start DynamicSupervisor for transactions
      {DynamicSupervisor, strategy: :one_for_one, name: ContaBot.Action.Transaction.Workers},
      # Start the Finch HTTP client for sending emails
      {Finch, name: ContaBot.Finch},
      ExGram,
      {ContaBot.Action, method: :polling, token: get_token()}
    ]

    opts = [strategy: :one_for_one, name: ContaBot.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp get_token do
    Application.get_env(:ex_gram, :token) ||
      raise """
      TOKEN WAS NOT CONFIGURED!!!
      """
  end
end
