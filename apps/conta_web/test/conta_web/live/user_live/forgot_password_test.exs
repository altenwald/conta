defmodule ContaWeb.UserLive.ForgotPasswordTest do
  use ContaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Conta.AccountsFixtures

  alias Conta.Accounts
  alias Conta.Repo

  describe "Forgot password page" do
    test "renders email page", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/reset-password")

      assert html =~ "Reset Password"
      assert has_element?(lv, ~s|a[href="#{~p"/register"}"]|, "Register")
      assert has_element?(lv, ~s|a[href="#{~p"/signin"}"]|, "Sign in")
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(insert(:user) |> confirm_user())
        |> live(~p"/reset-password")
        |> follow_redirect(conn, ~p"/")

      assert {:ok, _conn} = result
    end
  end

  describe "Reset link" do
    setup do
      %{user: insert(:user) |> confirm_user()}
    end

    test "sends a new reset password token", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/reset-password")

      {:ok, conn} =
        lv
        |> form("#reset_password_form", user: %{"email" => user.email})
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "If your email is in our system"

      assert Repo.get_by!(Accounts.UserToken, user_id: user.id).context ==
               "reset_password"
    end

    test "does not send reset password token if email is invalid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/reset-password")

      {:ok, conn} =
        lv
        |> form("#reset_password_form", user: %{"email" => "unknown@example.com"})
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "If your email is in our system"
      assert Repo.all(Accounts.UserToken) == []
    end
  end
end
