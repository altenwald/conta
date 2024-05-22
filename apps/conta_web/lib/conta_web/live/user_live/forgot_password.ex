defmodule ContaWeb.UserLive.ForgotPassword do
  use ContaWeb, :live_view

  alias Conta.Accounts

  def render(assigns) do
    ~H"""
    <section class="hero is-fullheight">
      <div :if={assigns[:error_message]} class="notification is-danger">
        <p><%= @error_message %></p>
      </div>
      <div class="hero-body">
        <div class="container">
          <div class="columns is-centered">
            <div class="column is-6-tablet is-5-desktop is-4-widscreen">
              <h1 class="is-size-3 mb-3"><%= gettext("Reset Password") %></h1>
              <div class="box">
                <.simple_form for={@form} id="reset_password_form" phx-submit="send_email">
                  <.input field={@form[:email]} type="email" label="Email" required />
                  <:actions>
                    <div class="has-text-right is-full-width">
                      <.button phx-disable-with={gettext("Sending...")} class="is-primary">
                        <%= gettext("Send password reset instructions") %>
                      </.button>
                    </div>
                  </:actions>
                </.simple_form>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"))}
  end

  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/reset-password/#{&1}")
      )
    end

    info =
      gettext(
        "If your email is in our system, you will receive instructions to reset your password shortly."
      )

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/")}
  end
end
