defmodule ContaWeb.UserLive.Confirmation do
  use ContaWeb, :live_view

  alias Conta.Accounts

  def render(%{live_action: :edit} = assigns) do
    ~H"""
    <section class="hero is-fullheight">
      <div :if={assigns[:error_message]} class="notification is-danger">
        <p><%= @error_message %></p>
      </div>
      <div class="hero-body">
        <div class="container">
          <div class="columns is-centered">
            <div class="column is-6-tablet is-5-desktop is-4-widscreen">
              <h1 class="is-size-3 mb-3"><%= gettext("Confirm Account") %></h1>
              <div class="box">
                <.simple_form for={@form} id="confirmation_form" phx-submit="confirm_account">
                  <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
                  <:actions>
                    <div class="has-text-centered is-full-width">
                      <.button phx-disable-with={gettext("Confirming...")} class="is-primary">
                        <%= gettext("Confirm my account") %>
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

  def mount(%{"token" => token}, _session, socket) do
    form = to_form(%{"token" => token}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: nil]}
  end

  # Do not log in the user after confirmation to avoid a
  # leaked token giving the user access to the account.
  def handle_event("confirm_account", %{"user" => %{"token" => token}}, socket) do
    case Accounts.confirm_user(token) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("User confirmed successfully."))
         |> redirect(to: ~p"/signin")}

      :error ->
        # If there is a current user and the account was already confirmed,
        # then odds are that the confirmation link was already visited, either
        # by some automation or by the user themselves, so we redirect without
        # a warning message.
        case socket.assigns do
          %{current_user: %{confirmed_at: confirmed_at}} when not is_nil(confirmed_at) ->
            {:noreply, redirect(socket, to: ~p"/")}

          %{} ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("User confirmation link is invalid or it has expired."))
             |> redirect(to: ~p"/")}
        end
    end
  end
end
