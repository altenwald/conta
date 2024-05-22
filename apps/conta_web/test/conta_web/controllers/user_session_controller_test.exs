defmodule ContaWeb.UserSessionControllerTest do
  use ContaWeb.ConnCase, async: true

  import Conta.AccountsFixtures

  setup do
    %{
      user: insert(:user),
      user_confirmed: insert(:user) |> confirm_user()
    }
  end

  describe "POST /signin" do
    test "signs the user in", %{conn: conn, user_confirmed: user} do
      conn =
        post(conn, ~p"/signin", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/logout"
    end

    test "cannot signs the user in until it confirms", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/signin", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      _response = html_response(conn, 302)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "The user must be confirmed."
    end

    test "signs the user in with remember me", %{conn: conn, user_confirmed: user} do
      conn =
        post(conn, ~p"/signin", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
      assert conn.resp_cookies["_conta_web_user_remember_me"]
    end

    test "logs the user in with return to", %{conn: conn, user_confirmed: user} do
      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/signin", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "login following registration cannot login", %{conn: conn, user: user} do
      conn =
        conn
        |> post(~p"/signin", %{
          "_action" => "registered",
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Account created successfully"
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      refute response =~ user.email
      refute response =~ ~p"/users/settings"
      refute response =~ ~p"/logout"
    end

    test "login following password update", %{conn: conn, user_confirmed: user} do
      conn =
        conn
        |> post(~p"/signin", %{
          "_action" => "password_updated",
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Password updated successfully"
    end

    test "redirects to login page with invalid credentials", %{conn: conn} do
      conn =
        post(conn, ~p"/signin", %{
          "user" => %{"email" => "invalid@email.com", "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/signin"
    end
  end

  describe "GET /logout" do
    test "logs the user out", %{conn: conn, user_confirmed: user} do
      conn = conn |> log_in_user(user) |> get(~p"/logout")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = get(conn, ~p"/logout")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
