defmodule ContaWeb.ContactLive.Index do
  use ContaWeb, :live_view

  require Logger

  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Directory
  alias Conta.Projector.Directory.Contact

  @impl true
  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(Conta.PubSub, "event:contact_set")
    {:ok, stream(socket, :directory_contacts, Directory.list_contacts())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    set_contact = Directory.get_set_contact(id)

    socket
    |> assign(:page_title, gettext("Edit Contact"))
    |> assign(:company_nif, set_contact.company_nif)
    |> assign(:set_contact, set_contact)
  end

  defp apply_action(socket, :new, _params) do
    set_contact = Directory.new_set_contact()

    socket
    |> assign(:page_title, gettext("New Contact"))
    |> assign(:company_nif, set_contact.company_nif)
    |> assign(:set_contact, set_contact)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Directory Contacts")
    |> assign(:set_contact, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => contact_id, "dom_id" => dom_id}, socket) do
    with %Contact{} = contact <- Directory.get_contact(contact_id),
         :ok <- dispatch(Directory.get_remove_contact(contact)) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Contact removed successfully"))
       |> stream_delete_by_dom_id(:directory_contacts, dom_id)}
    else
      error ->
        Logger.error("cannot remove: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, gettext("Cannot remove the contact"))}
    end
  end

  @impl true
  def handle_info({:contact_set, contact}, socket) do
    Logger.debug("adding contact to the stream #{contact.name}")
    {:noreply, stream_insert(socket, :directory_contacts, contact, at: 0)}
  end
end
