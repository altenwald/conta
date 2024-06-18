defmodule Conta.Commanded.Application do
  use Commanded.Application,
    otp_app: :conta,
    event_store: Application.compile_env!(:conta, :event_store)

  router(Conta.Commanded.Router)
end
