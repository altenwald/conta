defmodule ContaWeb.UserLive.Signin do
  use ContaWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="hero min-h-screen">
      <div class="hero-content flex-col lg:flex-row-reverse">
        <div class="text-center lg:text-left">
          <h1 class="text-5xl font-bold">{gettext("Sign In")}</h1>
          <p class="py-6"><%# TODO write an eloquent phrase here :-) %></p>
        </div>
        <div class="card bg-base-100 w-full max-w-sm shrink-0 shadow-2xl">
          <div class="card-body">
            <.simple_form for={@form} id="login_form" action={~p"/signin"} phx-update="ignore">
              <.input field={@form[:email]} type="email" label={gettext("Email")} required />
              <.input field={@form[:password]} type="password" label={gettext("Password")} required />

              <:actions>
                <.input
                  field={@form[:remember_me]}
                  type="checkbox"
                  label={gettext("Keep me logged in")}
                />
                <div class="has-text-right full-width">
                  <.link href={~p"/reset-password"} class="button is-ghost">
                    <%= gettext("Forgot your password?") %>
                  </.link>
                </div>
                <div class="has-text-right full-width">
                  <button phx-disable-with={gettext("Logging in...")} class="btn btn-primary">
                    {gettext("Sign in")}
                  </button>
                </div>
              </:actions>
            </.simple_form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end
