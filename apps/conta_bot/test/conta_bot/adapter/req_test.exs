defmodule ContaBot.Adapter.ReqTest do
  use ExUnit.Case, async: true

  test "encodes multipart body with file_content and string fields without error" do
    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "name=\"photo\"; filename=\"pnl.png\""
      assert body =~ "name=\"chat_id\""

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{ok: true, result: %{message_id: 1}}))
    end

    body =
      {:multipart,
       [
         {:file_content, "photo", <<137, 80, 78, 71>>, "pnl.png"},
         {"chat_id", "123456"}
       ]}

    assert {:ok, %{message_id: 1}} =
             ContaBot.Adapter.Req.request(:post, "/bot123/sendPhoto", body,
               plug: plug,
               base_url: "http://localhost"
             )
  end
end
