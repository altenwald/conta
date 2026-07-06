defmodule ContaWeb.UserLive.Registration do
  use ContaWeb, :live_view

  alias Conta.Accounts
  alias Conta.Accounts.User

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
              {gettext("Registration")}
            </h1>

            <.simple_form
              for={@form}
              id="registration_form"
              phx-submit="save"
              phx-change="validate"
              phx-trigger-action={@trigger_submit}
              action={~p"/signin?_action=registered"}
              method="post"
            >
              <.error :if={@check_errors}>
                {gettext("Oops, something went wrong! Please check the errors below.")}
              </.error>

              <.input field={@form[:email]} type="email" label={gettext("Email")} required />
              <.input field={@form[:password]} type="password" label={gettext("Password")} required />

              <:actions>
                <div class="flex flex-col gap-4 w-full mt-2">
                  <.link href={~p"/users/confirm"} class="link link-primary text-sm text-center">
                    {gettext("Didn't you receive the confirmation email?")}
                  </.link>
                  <div class="card-actions">
                    <.button phx-disable-with={gettext("Creating account...")} class="btn-primary w-full">
                      {gettext("Create an account")}
                    </.button>
                  </div>
                </div>
              </:actions>
            </.simple_form>
          </div>
        </div>

        <p class="text-center mt-6 text-base-content opacity-70">
          {gettext("Already have an account?")}
          <.link href={~p"/signin"} class="link link-primary font-semibold">
            {gettext("Sign in")}
          </.link>
        </p>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{})

    socket =
      socket
      |> assign(trigger_submit: false, check_errors: false)
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &url(~p"/users/confirm/#{&1}")
          )

        changeset = Accounts.change_user_registration(user)
        {:noreply, socket |> assign(trigger_submit: true) |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end
end
