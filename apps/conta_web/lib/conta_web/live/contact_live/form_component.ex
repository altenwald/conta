defmodule ContaWeb.ContactLive.FormComponent do
  use ContaWeb, :live_component
  import Conta.Commanded.Application, only: [dispatch: 1]
  require Logger

  alias Conta.Command.SetContact

  @impl true
  def render(assigns) do
    ~H"""
    <div class="modal is-active">
      <div class="modal-background"></div>
      <div class="modal-card">
        <header class="modal-card-head">
          <h2><%= @title %></h2>
        </header>
        <section class="modal-card-body">
          <.simple_form
            for={@form}
            id="contact-form"
            phx-target={@myself}
            phx-change="validate"
            phx-submit="save"
          >
            <.input
              field={@form[:company_nif]}
              type="text"
              label={gettext("Company NIF")}
              disabled="true"
            />
            <.input field={@form[:nif]} type="text" label={gettext("Contact NIF")} />
            <.input field={@form[:name]} type="text" label={gettext("Name")} />
            <.input field={@form[:intracommunity]} type="checkbox" label={gettext("Intracommunity?")} />
            <.input field={@form[:address]} type="text" label={gettext("Address")} />
            <.input field={@form[:postcode]} type="text" label={gettext("Postcode")} />
            <.input field={@form[:city]} type="text" label={gettext("City")} />
            <.input field={@form[:state]} type="text" label={gettext("State")} />
            <.input
              field={@form[:country]}
              type="select"
              options={list_countries()}
              label={gettext("Country")}
              phx-debounce={500}
            />
          </.simple_form>
        </section>
        <footer class="modal-card-foot is-at-right">
          <.button form="contact-form" class="is-primary" phx-disable-with={gettext("Saving...")}>
            <%= gettext("Save Contact") %>
          </.button>
          <.link class="button" patch={@patch}>
            <%= gettext("Cancel") %>
          </.link>
        </footer>
      </div>
    </div>
    """
  end

  defp list_countries do
    #  TODO frequent countries?
    Countries.all()
    |> Enum.map(&{&1.name, &1.alpha2})
    |> Enum.sort()
  end

  @impl true
  def update(%{set_contact: set_contact} = assigns, socket) do
    changeset = SetContact.changeset(set_contact, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       params: %{"company_nif" => assigns.company_nif},
       set_contact: set_contact
     )
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"set_contact" => params}, socket) do
    validate(socket, params)
  end

  def handle_event("save", %{"set_contact" => params}, socket) do
    save_contact(socket, socket.assigns.action, params)
  end

  defp validate(socket, params) do
    params = Map.put(params, "company_nif", socket.assigns.company_nif)

    changeset =
      socket.assigns.set_contact
      |> SetContact.changeset(params)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign_form(changeset)
      |> assign(params: params)

    {:noreply, socket}
  end

  defp save_contact(socket, :edit, params) do
    params = Map.put(params, "company_nif", socket.assigns.company_nif)
    changeset = SetContact.changeset(socket.assigns.set_contact, params)

    if changeset.valid? and dispatch(SetContact.to_command(changeset)) == :ok do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Contact modified successfully"))
       |> push_patch(to: socket.assigns.patch)}
    else
      Logger.debug("changeset errors: #{inspect(changeset.errors)}")
      changeset = Map.put(changeset, :action, :validate)
      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_contact(socket, :new, params) do
    params = Map.put(params, "company_nif", socket.assigns.company_nif)
    changeset = SetContact.changeset(socket.assigns.set_contact, params)

    if changeset.valid? and dispatch(SetContact.to_command(changeset)) == :ok do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Contact created successfully"))
       |> push_patch(to: socket.assigns.patch)}
    else
      Logger.debug("changeset errors: #{inspect(changeset.errors)}")
      changeset = Map.put(changeset, :action, :validate)
      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
