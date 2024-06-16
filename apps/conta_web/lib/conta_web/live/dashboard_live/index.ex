defmodule ContaWeb.DashboardLive.Index do
  use ContaWeb, :live_view
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    currency = :EUR
    {:ok, assign(socket, :currency, currency)}
  end
end
