defmodule ContaWeb.UserLive.Settings do
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
            <div class="column is-12-tablet is-10-desktop is-8-widscreen">
              <h1 class="is-size-3 mb-3"><%= gettext("Settings") %></h1>
              <div class="box">
                <h2 class="is-size-4 mb-3"><%= gettext("Update email") %></h2>
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
                    <div class="has-text-right is-full-width">
                      <.button phx-disable-with={gettext("Changing...")} class="is-primary">
                        <%= gettext("Change Email") %>
                      </.button>
                    </div>
                  </:actions>
                </.simple_form>
              </div>
              <div class="box">
                <h2 class="is-size-4 mb-3"><%= gettext("Update Password") %></h2>
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
                    <div class="has-text-right is-full-width">
                      <.button phx-disable-with={gettext("Changing...")} class="is-primary">
                        <%= gettext("Change Password") %>
                      </.button>
                    </div>
                  </:actions>
                </.simple_form>
              </div>
              <div class="box">
                <div class="content">
                  <h2 class="is-size-4 mb-3"><%= gettext("API Token") %></h2>
                  <p :if={@api_token}>
                    <strong>
                      <%= gettext("Last token was generated %{date}.", date: @api_token.inserted_at) %>
                    </strong>
                  </p>
                  <p :if={@api_token}>
                    <strong>
                      <%= gettext(
                        "It will expire at %{expires}",
                        expires: Accounts.UserToken.when_it_expires(@api_token)
                      ) %>
                    </strong>
                  </p>
                  <p>
                    <%= gettext(
                      "You MUST save the token generated because it is not stored in the database."
                    ) %>
                  </p>
                  <p :if={assigns[:token]}>
                    <strong><%= @token %></strong>
                  </p>
                  <p>
                    <button
                      type="button"
                      class={["button", if(@api_token, do: "is-danger", else: "is-primary")]}
                      phx-click="generate_token"
                    >
                      <%= gettext("Generate") %>
                    </button>
                  </p>
                  <p>
                    <%= gettext("If a new token is generated the previous one will be removed.") %>
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
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
