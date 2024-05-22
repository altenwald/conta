defmodule ContaWeb.UserLive.RegistrationTest do
  use ContaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Conta.AccountsFixtures

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/register")

      assert html =~ "Register"
      assert html =~ "Sign in"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(insert(:user) |> confirm_user())
        |> live(~p"/register")
        |> follow_redirect(conn, "/")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: %{"email" => "with spaces", "password" => "too short"})

      assert result =~ "Register"
      assert result =~ "must have the @ sign and no spaces"
      assert result =~ "should be at least 12 character"
    end
  end

  describe "register user" do
    test "creates account", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/register")

      email = unique_user_email()
      password = valid_user_password()
      form = form(lv, "#registration_form", user: %{email: email, password: password})

      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Account created successfully!"
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/register")

      user = insert(:user, %{email: "test@email.com"})

      result =
        lv
        |> form("#registration_form",
          user: %{"email" => user.email, "password" => valid_user_password()}
        )
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Sign in button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/register")

      {:ok, conn} =
        lv
        |> element(~s|a:fl-contains("Sign in")|)
        |> render_click()
        |> follow_redirect(conn)

      assert html_response(conn, 200) =~ "Sign in"
    end
  end
end
