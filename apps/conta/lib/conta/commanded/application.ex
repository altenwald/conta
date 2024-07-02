defmodule Conta.Commanded.Application do
  use Commanded.Application,
    otp_app: :conta,
    event_store: Application.compile_env!(:conta, :event_store),
    default_dispatch_opts: [timeout: 30_000]

  router(Conta.Commanded.Router)
end
