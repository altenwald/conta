defmodule Conta.Repo do
  use Ecto.Repo,
    otp_app: :conta,
    adapter: Ecto.Adapters.Postgres
end
