defmodule ContaWeb.UserLive.SigninTest do
  use ContaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Conta.AccountsFixtures

  describe "Sign in page" do
    test "renders log in page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/signin")

      assert html =~ "Sign in"
      assert html =~ "Register"
      assert html =~ "Forgot your password?"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(insert(:user) |> confirm_user())
        |> live(~p"/signin")
        |> follow_redirect(conn, "/")

      assert {:ok, _conn} = result
    end
  end

  describe "user signin" do
    test "redirects if user signin with valid credentials", %{conn: conn} do
      password = "123456789abcd"
      user = insert(:user, %{hashed_password: hashed_password(password)}) |> confirm_user()

      {:ok, lv, _html} = live(conn, ~p"/signin")

      form =
        form(lv, "#login_form", user: %{email: user.email, password: password, remember_me: true})

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to login page with a flash error if there are no valid credentials", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/signin")

      form =
        form(lv, "#login_form",
          user: %{email: "test@email.com", password: "123456", remember_me: true}
        )

      conn = submit_form(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"

      assert redirected_to(conn) == "/signin"
    end
  end

  describe "login navigation" do
    test "redirects to registration page when the Register button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/signin")

      {:ok, conn} =
        lv
        |> element(~s|a:not([class*='navbar'])|, "Register")
        |> render_click()
        |> follow_redirect(conn, ~p"/register")

      response = html_response(conn, 200)
      assert response =~ "Register"
    end

    test "redirects to forgot password page when the Forgot Password button is clicked", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/signin")

      {:ok, conn} =
        lv
        |> element(~s|a:fl-contains("Forgot your password?")|)
        |> render_click()
        |> follow_redirect(conn, ~p"/reset-password")

      assert conn.resp_body =~ "Reset Password"
    end
  end
end
