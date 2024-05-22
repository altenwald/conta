defmodule ContaWeb.UserSessionController do
  use ContaWeb, :controller

  alias Conta.Accounts
  alias ContaWeb.UserAuth

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, gettext("Account created successfully!"))
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, gettext("Password updated successfully!"))
  end

  def create(conn, params) do
    create(conn, params, nil)
  end

  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params
    user = Accounts.get_user_by_email_and_password(email, password)

    cond do
      is_nil(user) ->
        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:error, gettext("Invalid email or password"))
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/signin")

      is_nil(user.confirmed_at) and is_nil(info) ->
        # Trying to loging and the user is still not confirmed
        conn
        |> put_flash(:error, gettext("The user must be confirmed. Review your email."))
        |> redirect(to: ~p"/")

      is_nil(user.confirmed_at) ->
        # We need confirmation before let the user in
        conn
        |> put_flash(:info, info)
        |> redirect(to: ~p"/")

      :else ->
        conn
        |> put_flash(:info, info || gettext("Welcome back!"))
        |> UserAuth.log_in_user(user, user_params)
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, gettext("Logged out successfully."))
    |> UserAuth.log_out_user()
  end
end
