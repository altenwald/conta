defmodule ContaWeb.UserLive.Registration do
  use ContaWeb, :live_view

  alias Conta.Accounts
  alias Conta.Accounts.User

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
              <h1 class="is-size-3 mb-3"><%= gettext("Registration") %></h1>
              <div class="box">
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
                    <%= gettext("Oops, something went wrong! Please check the errors below.") %>
                  </.error>

                  <.input field={@form[:email]} type="email" label={gettext("Email")} required />
                  <.input field={@form[:password]} type="password" label={gettext("Password")} required />

                  <:actions>
                    <div class="has-text-right full-width">
                      <.link href={~p"/users/confirm"} class="button is-ghost">
                        <%= gettext("Didn't you receive the confirmation email?") %>
                      </.link>
                    </div>
                  </:actions>
                  <:actions>
                    <div class="has-text-right is-full-width">
                      <.button phx-disable-with={gettext("Creating account...")} class="is-primary">
                        <%= gettext("Create an account") %>
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
