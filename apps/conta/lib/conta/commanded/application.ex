defmodule Conta.Commanded.Application do
  use Commanded.Application,
    otp_app: :conta,
    event_store: [
      adapter: Commanded.EventStore.Adapters.EventStore,
      event_store: Conta.EventStore
    ]

  router(Conta.Commanded.Router)
end
