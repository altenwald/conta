defmodule ContaWeb.UserLive.ForgotPassword do
  use ContaWeb, :live_view

  alias Conta.Accounts

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-base-200 px-4 py-12">
      <div class="max-w-md w-full">
        <div :if={assigns[:error_message]} class="alert alert-error mb-6 shadow-lg">
          <.icon name="hero-exclamation-triangle" class="w-6 h-6" />
          <span>{@error_message}</span>
        </div>

        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h1 class="card-title text-3xl mb-6 justify-center text-base-content font-bold">
              {gettext("Reset Password")}
            </h1>

            <.simple_form for={@form} id="reset_password_form" phx-submit="send_email">
              <.input field={@form[:email]} type="email" label="Email" required />
              <:actions>
                <div class="card-actions w-full mt-4">
                  <.button phx-disable-with={gettext("Sending...")} class="btn-primary w-full">
                    {gettext("Send password reset instructions")}
                  </.button>
                </div>
              </:actions>
            </.simple_form>
          </div>
        </div>

        <p class="text-center mt-6 text-base-content opacity-70">
          <.link href={~p"/register"} class="link link-primary font-semibold mx-2">
            {gettext("Register")}
          </.link>
          |
          <.link href={~p"/signin"} class="link link-primary font-semibold mx-2">
            {gettext("Sign in")}
          </.link>
        </p>
      </div>
    </div>
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
      gettext("If your email is in our system, you will receive instructions to reset your password shortly.")

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/")}
  end
end
