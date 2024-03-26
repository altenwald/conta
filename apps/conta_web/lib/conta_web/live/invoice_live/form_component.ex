defmodule ContaWeb.InvoiceLive.FormComponent do
  use ContaWeb, :live_component

  alias Conta.Book
  alias Conta.Command.CreateInvoice
  alias Conta.Directory

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
            id="invoice-form"
            phx-target={@myself}
            phx-change="validate"
            phx-submit="save"
          >
            <.input field={@form[:invoice_number]} type="number" label={gettext("Invoice Number")} />
            <.input field={@form[:invoice_date]} type="date" label={gettext("Invoice Date")} />
            <.input field={@form[:due_date]} type="date" label={gettext("Due Date")} />
            <.input
              field={@form[:type]}
              type="select"
              label={gettext("Type")}
              options={[{gettext("Product"), "product"}, {gettext("Service"), "service"}]}
              prompt={gettext("Choose a type")}
            />
            <.input
              field={@form[:client_nif]}
              type="select"
              label={gettext("Client")}
              options={list_clients()}
              prompt={gettext("No client")}
            />
            <.input
              field={@form[:subtotal_price]}
              type="number"
              step=".01"
              label={gettext("Subtotal")}
            />
            <.input field={@form[:comments]} type="textarea" label={gettext("Comments")} />
          </.simple_form>
        </section>
      </div>
    </div>
    """
  end

  defp list_clients do
    Directory.list_contacts()
    |> Enum.map(&{&1.name, &1.slug})
  end

  @impl true
  def update(%{create_invoice: invoice} = assigns, socket) do
    changeset = CreateInvoice.changeset(invoice, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"create_invoice" => invoice_params}, socket) do
    changeset =
      socket.assigns.create_invoice
      |> CreateInvoice.changeset(invoice_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"create_invoice" => invoice_params}, socket) do
    save_invoice(socket, socket.assigns.action, invoice_params)
  end

  defp save_invoice(socket, :edit, invoice_params) do
    case Book.update_invoice(socket.assigns.invoice, invoice_params) do
      {:ok, invoice} ->
        notify_parent({:saved, invoice})

        {:noreply,
         socket
         |> put_flash(:info, "Invoice updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_invoice(socket, :new, invoice_params) do
    case Book.create_invoice(invoice_params) do
      {:ok, invoice} ->
        notify_parent({:saved, invoice})

        {:noreply,
         socket
         |> put_flash(:info, "Invoice created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
