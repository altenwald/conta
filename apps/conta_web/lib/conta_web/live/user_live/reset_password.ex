defmodule ContaWeb.UserLive.ResetPassword do
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

            <.simple_form
              for={@form}
              id="reset_password_form"
              phx-submit="reset_password"
              phx-change="validate"
            >
              <.error :if={@form.errors != []}>
                {gettext("Oops, something went wrong! Please check the errors below.")}
              </.error>

              <.input field={@form[:password]} type="password" label={gettext("New password")} required />
              <.input
                field={@form[:password_confirmation]}
                type="password"
                label={gettext("Confirm new password")}
                required
              />
              <:actions>
                <div class="card-actions w-full mt-4">
                  <.button phx-disable-with={gettext("Resetting...")} class="btn-primary w-full">
                    {gettext("Reset Password")}
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

  def mount(params, _session, socket) do
    socket = assign_user_and_token(socket, params)

    form_source =
      if user = socket.assigns[:user] do
        Accounts.change_user_password(user)
      else
        %{}
      end

    {:ok, assign_form(socket, form_source), temporary_assigns: [form: nil]}
  end

  # Do not log in the user after reset password to avoid a
  # leaked token giving the user access to the account.
  def handle_event("reset_password", %{"user" => user_params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, user_params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Password reset successfully."))
         |> redirect(to: ~p"/signin")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_password(socket.assigns.user, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_user_and_token(socket, %{"token" => token}) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      assign(socket, user: user, token: token)
    else
      socket
      |> put_flash(:error, gettext("Reset password link is invalid or it has expired."))
      |> redirect(to: ~p"/")
    end
  end

  defp assign_form(socket, %{} = source) do
    assign(socket, :form, to_form(source, as: "user"))
  end
end
