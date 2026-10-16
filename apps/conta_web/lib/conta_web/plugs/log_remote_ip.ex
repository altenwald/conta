defmodule ContaWeb.Plugs.LogRemoteIp do
  @moduledoc """
  Puts the address of the visitor in the Logger metadata of the request process, so that the lines Phoenix writes for
  the request (`GET /...`, `Sent 200 in ...`) carry it when `:remote_ip` is listed in the metadata of the logger.

  It must run after `RemoteIp`, which turns the proxy headers into `conn.remote_ip`, and before `Plug.Telemetry`,
  which writes the first line.
  """
  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{remote_ip: remote_ip} = conn, _opts) do
    Logger.metadata(remote_ip: remote_ip |> :inet.ntoa() |> to_string())
    conn
  end
end
