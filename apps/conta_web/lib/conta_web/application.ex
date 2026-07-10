defmodule ContaWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @default_pdf_pool_size 3
  @default_pdf_checkout_timeout 10_000
  @default_pdf_init_timeout 10_000

  @impl true
  def start(_type, _args) do
    children = [
      ContaWeb.Telemetry,
      # Start a worker by calling: ContaWeb.Worker.start_link(arg)
      # {ContaWeb.Worker, arg},
      # Start to serve requests, typically the last entry
      ContaWeb.Endpoint,
      {ChromicPDF, chromic_pdf_opts()}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ContaWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp chromic_pdf_opts do
    [
      session_pool: [
        size: Application.get_env(:conta_web, :pdf_pool_size, @default_pdf_pool_size),
        # The pool spawns all of its Chrome instances concurrently at once. On a
        # dev machine under load (Postgres, the LiveView app itself, asset
        # watchers, ...) initializing 3 Chrome processes in parallel can take
        # longer than the library's 5s default, so every worker fails to boot,
        # crashes (leaking its Chrome process before cleanup catches up), and
        # NimblePool just keeps spawning replacements. 10s gives enough headroom
        # for concurrent cold starts without masking a truly hung Chrome.
        checkout_timeout:
          Application.get_env(:conta_web, :pdf_checkout_timeout, @default_pdf_checkout_timeout),
        init_timeout: Application.get_env(:conta_web, :pdf_init_timeout, @default_pdf_init_timeout)
      ]
    ]
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ContaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
