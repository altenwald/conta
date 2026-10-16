defmodule ContaWeb.Plugs.LogRemoteIpTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias ContaWeb.Plugs.LogRemoteIp

  setup do
    Logger.reset_metadata()
    :ok
  end

  test "an IPv4 address goes to the logger metadata" do
    conn = %{conn(:get, "/") | remote_ip: {203, 0, 113, 9}}
    assert ^conn = LogRemoteIp.call(conn, LogRemoteIp.init([]))
    assert Logger.metadata()[:remote_ip] == "203.0.113.9"
  end

  test "an IPv6 address goes to the logger metadata" do
    conn = %{conn(:get, "/") | remote_ip: {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1}}
    LogRemoteIp.call(conn, [])
    assert Logger.metadata()[:remote_ip] == "2001:db8::1"
  end

  test "behind RemoteIp it is the visitor, not the proxy" do
    conn =
      conn(:get, "/")
      |> put_req_header("x-forwarded-for", "203.0.113.9")
      |> Map.put(:remote_ip, {192, 168, 1, 40})
      |> RemoteIp.call(RemoteIp.init([]))
      |> LogRemoteIp.call([])

    assert conn.remote_ip == {203, 0, 113, 9}
    assert Logger.metadata()[:remote_ip] == "203.0.113.9"
  end

  test "a forged chain is read from the right: the address a trusted proxy added wins" do
    conn =
      conn(:get, "/")
      |> put_req_header("x-forwarded-for", "9.9.9.9, 203.0.113.9")
      |> Map.put(:remote_ip, {192, 168, 1, 40})
      |> RemoteIp.call(RemoteIp.init([]))
      |> LogRemoteIp.call([])

    assert conn.remote_ip == {203, 0, 113, 9}
    assert Logger.metadata()[:remote_ip] == "203.0.113.9"
  end
end
