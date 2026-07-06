defmodule ContaWeb.UserLive.Signin do
  use ContaWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-base-200 px-4">
      <div class="max-w-md w-full">
        <div :if={assigns[:error_message]} class="alert alert-error mb-6 shadow-lg">
          <.icon name="hero-exclamation-triangle" class="w-6 h-6" />
          <span>{@error_message}</span>
        </div>

        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h1 class="card-title text-3xl mb-6 justify-center text-base-content font-bold">
              {gettext("Sign In")}
            </h1>

            <.simple_form for={@form} id="login_form" action={~p"/signin"} phx-update="ignore">
              <.input field={@form[:email]} type="email" label={gettext("Email")} required />
              <.input field={@form[:password]} type="password" label={gettext("Password")} required />

              <:actions>
                <div class="flex items-center justify-between w-full">
                  <.input
                    field={@form[:remember_me]}
                    type="checkbox"
                    control_label={gettext("Keep me logged in")}
                    offset={false}
                  />
                  <.link href={~p"/reset-password"} class="link link-primary text-sm">
                    {gettext("Forgot your password?")}
                  </.link>
                </div>
              </:actions>
              <:actions>
                <div class="card-actions justify-end w-full mt-4">
                  <.button type="submit" phx-disable-with={gettext("Logging in...")} class="btn-primary w-full">
                    {gettext("Sign in")}
                  </.button>
                </div>
              </:actions>
            </.simple_form>
          </div>
        </div>

        <p class="text-center mt-6 text-base-content opacity-70">
          {gettext("Don't have an account?")}
          <.link href={~p"/register"} class="link link-primary font-semibold">
            {gettext("Register")}
          </.link>
        </p>
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
