defmodule ContaWeb.UserLive.Settings do
  use ContaWeb, :live_view

  alias Conta.Accounts

  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8 max-w-4xl">
      <div :if={assigns[:error_message]} class="alert alert-error mb-6 shadow-lg">
        <.icon name="hero-exclamation-triangle" class="w-6 h-6" />
        <span>{@error_message}</span>
      </div>

      <header class="mb-8">
        <h1 class="text-3xl font-bold text-base-content">{gettext("Settings")}</h1>
        <p class="text-base-content opacity-70">{gettext("Manage your account settings and API tokens.")}</p>
      </header>

      <div class="flex flex-col gap-8">
        <div class="card bg-base-100 shadow-xl border border-base-200">
          <div class="card-body">
            <h2 class="card-title text-xl mb-4">{gettext("Update email")}</h2>
            <.simple_form
              for={@email_form}
              id="email_form"
              phx-submit="update_email"
              phx-change="validate_email"
            >
              <.input field={@email_form[:email]} type="email" label={gettext("Email")} required />
              <.input
                field={@email_form[:current_password]}
                name="current_password"
                id="current_password_for_email"
                type="password"
                label={gettext("Current password")}
                value={@email_form_current_password}
                required
              />
              <:actions>
                <div class="card-actions justify-end w-full mt-4">
                  <.button phx-disable-with={gettext("Changing...")} class="btn-primary">
                    {gettext("Change Email")}
                  </.button>
                </div>
              </:actions>
            </.simple_form>
          </div>
        </div>

        <div class="card bg-base-100 shadow-xl border border-base-200">
          <div class="card-body">
            <h2 class="card-title text-xl mb-4">{gettext("Update Password")}</h2>
            <.simple_form
              for={@password_form}
              id="password_form"
              action={~p"/signin?_action=password_updated"}
              method="post"
              phx-change="validate_password"
              phx-submit="update_password"
              phx-trigger-action={@trigger_submit}
            >
              <input
                name={@password_form[:email].name}
                type="hidden"
                id="hidden_user_email"
                value={@current_email}
              />
              <.input
                field={@password_form[:password]}
                type="password"
                label={gettext("New password")}
                required
              />
              <.input
                field={@password_form[:password_confirmation]}
                type="password"
                label={gettext("Confirm new password")}
              />
              <.input
                field={@password_form[:current_password]}
                name="current_password"
                type="password"
                label={gettext("Current password")}
                id="current_password_for_password"
                value={@current_password}
                required
              />
              <:actions>
                <div class="card-actions justify-end w-full mt-4">
                  <.button phx-disable-with={gettext("Changing...")} class="btn-primary">
                    {gettext("Change Password")}
                  </.button>
                </div>
              </:actions>
            </.simple_form>
          </div>
        </div>

        <div class="card bg-base-100 shadow-xl border border-base-200">
          <div class="card-body">
            <h2 class="card-title text-xl mb-4">{gettext("API Token")}</h2>
            <div class="space-y-4">
              <div :if={@api_token} class="stats shadow bg-base-200 w-full">
                <div class="stat">
                  <div class="stat-title text-sm opacity-70">{gettext("Last generated")}</div>
                  <div class="stat-value text-base opacity-90">{@api_token.inserted_at}</div>
                </div>
                <div class="stat">
                  <div class="stat-title text-sm opacity-70">{gettext("Expires at")}</div>
                  <div class="stat-value text-base opacity-90">
                    {Accounts.UserToken.when_it_expires(@api_token)}
                  </div>
                </div>
              </div>

              <div class="alert alert-warning shadow-sm">
                <.icon name="hero-information-circle" class="w-6 h-6 flex-shrink-0" />
                <span class="text-sm">
                  {gettext("You MUST save the token generated because it is not stored in the database.")}
                </span>
              </div>

              <div :if={assigns[:token]} class="alert alert-info shadow-sm break-all font-mono text-center">
                <strong>{@token}</strong>
              </div>

              <div class="card-actions items-center justify-between mt-4">
                <p class="text-xs opacity-60">
                  {gettext("Generating a new token will invalidate the previous one.")}
                </p>
                <button
                  type="button"
                  class={["btn", if(@api_token, do: "btn-error btn-outline", else: "btn-primary")]}
                  phx-click="generate_token"
                >
                  {gettext("Generate New Token")}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_user, token) do
        :ok ->
          put_flash(socket, :info, gettext("Email changed successfully."))

        :error ->
          put_flash(socket, :error, gettext("Email change link is invalid or it has expired."))
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    email_changeset = Accounts.change_user_email(user)
    password_changeset = Accounts.change_user_password(user)
    api_token = Accounts.fetch_api_token_by_user(user)

    socket =
      socket
      |> assign(:current_password, nil)
      |> assign(:email_form_current_password, nil)
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:api_token, api_token)

    {:ok, socket}
  end

  def handle_event("validate_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    email_form =
      socket.assigns.current_user
      |> Accounts.change_user_email(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form, email_form_current_password: password)}
  end

  def handle_event("update_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied_user} ->
        Accounts.deliver_user_update_email_instructions(
          applied_user,
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = gettext("A link to confirm your email change has been sent to the new address.")
        {:noreply, socket |> put_flash(:info, info) |> assign(email_form_current_password: nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :email_form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    password_form =
      socket.assigns.current_user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form, current_password: password)}
  end

  def handle_event("update_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        password_form =
          user
          |> Accounts.change_user_password(user_params)
          |> to_form()

        {:noreply, assign(socket, trigger_submit: true, password_form: password_form)}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset))}
    end
  end

  def handle_event("generate_token", _params, socket) do
    user = socket.assigns.current_user
    token = Accounts.create_user_api_token(user)
    api_token = Accounts.fetch_api_token_by_user(user)
    {:noreply, assign(socket, token: token, api_token: api_token)}
  end
end
