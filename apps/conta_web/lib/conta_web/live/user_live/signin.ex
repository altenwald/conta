defmodule ContaWeb.UserLive.Signin do
  use ContaWeb, :live_view

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
              <h1 class="is-size-3 mb-3"><%= gettext("Sign In") %></h1>
              <div class="box">
                <.simple_form for={@form} id="login_form" action={~p"/signin"} phx-update="ignore">
                  <.input field={@form[:email]} type="email" label={gettext("Email")} required />
                  <.input field={@form[:password]} type="password" label={gettext("Password")} required />

                  <:actions>
                    <.input
                      field={@form[:remember_me]}
                      type="checkbox"
                      control_label={gettext("Keep me logged in")}
                    />
                    <div class="has-text-right full-width">
                      <.link href={~p"/reset-password"} class="button is-ghost">
                        <%= gettext("Forgot your password?") %>
                      </.link>
                    </div>
                  </:actions>
                  <:actions>
                    <div class="has-text-right full-width">
                      <.button type="submit" phx-disable-with={gettext("Logging in...")} class="button is-primary">
                        <%= gettext("Sign in") %>
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
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end
