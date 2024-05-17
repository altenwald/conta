defmodule ContaWeb.InvoiceLive.FormComponent do
  use ContaWeb, :live_component
  import Conta.Commanded.Application, only: [dispatch: 1]
  require Logger

  alias Conta.Book
  alias Conta.Command.SetInvoice
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
            <.input field={@form[:nif]} type="text" label={gettext("Company NIF")} disabled="true" />
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
              field={@form[:payment_method]}
              type="select"
              label={gettext("Payment Method")}
              options={list_payment_methods(@company_nif)}
              prompt={gettext("Choose a payment method...")}
            />
            <.input
              field={@form[:template]}
              type="select"
              label={gettext("Template")}
              options={list_templates(@company_nif)}
              prompt={gettext("Choose a template...")}
            />
            <.input
              field={@form[:currency]}
              type="select"
              label={gettext("Currency")}
              options={list_currencies()}
              prompt={gettext("Choose a currency...")}
            />
            <.input
              field={@form[:subtotal_price]}
              type="number"
              step=".01"
              label={gettext("Subtotal")}
            />
            <.input field={@form[:tax_price]} type="number" step=".01" label={gettext("Tax Price")} />
            <.input
              field={@form[:total_price]}
              type="number"
              step=".01"
              label={gettext("Total Price")}
            />
            <.input
              :if={@form[:client_nif].value in [nil, ""]}
              field={@form[:destination_country]}
              type="select"
              label={gettext("Client Country")}
              options={list_countries()}
              prompt={gettext("Choose a country...")}
            />
            <.input
              :if={@form[:client_nif].value not in [nil, ""]}
              field={@form[:destination_country]}
              type="hidden"
            />
            <div class="field is-horizontal">
              <div class="field-label is-normal">
                <label class="label"><%= gettext("Details") %></label>
              </div>
              <div class="field-body">
                <.link class="button" phx-target={@myself} phx-click="add_detail">
                  <%= gettext("Add Detail") %>
                </.link>
              </div>
            </div>
            <.inputs_for :let={d} field={@form[:details]}>
              <div class="columns">
                <div class="column is-one-fifth">
                  <.link
                    class="button is-danger"
                    phx-target={@myself}
                    phx-click="del_detail"
                    phx-value-index={d.index}
                  >
                    <%= gettext("Remove") %>
                  </.link>
                </div>
                <div class="column">
                  <.input field={d[:sku]} type="text" label={gettext("SKU")} />
                  <.input field={d[:description]} type="text" label={gettext("Description")} />
                  <.input field={d[:tax]} type="number" label={gettext("Tax (%)")} />
                  <.input
                    field={d[:base_price]}
                    type="number"
                    step=".01"
                    label={gettext("Base Price")}
                  />
                  <.input field={d[:units]} type="number" label={gettext("Units")} />
                  <.input field={d[:tax_price]} type="number" step=".01" label={gettext("Tax Price")} />
                  <.input
                    field={d[:total_price]}
                    type="number"
                    step=".01"
                    label={gettext("Total Price")}
                  />
                </div>
              </div>
            </.inputs_for>
            <.input field={@form[:comments]} type="textarea" label={gettext("Comments")} />
          </.simple_form>
        </section>
        <footer class="modal-card-foot is-at-right">
          <.button form="invoice-form" class="is-primary" phx-disable-with={gettext("Saving...")}>
            <%= gettext("Save Invoice") %>
          </.button>
          <.link class="button" patch={~p"/books/invoices"}>
            <%= gettext("Cancel") %>
          </.link>
        </footer>
      </div>
    </div>
    """
  end

  defp list_currencies do
    # TODO get more frequent currencies from database entries or put in a specific table/cache
    frequent = ~w[EUR USD GBP]a

    currencies =
      Money.Currency.all()
      |> Map.drop(frequent)
      |> Map.keys()

    for currency <- frequent ++ currencies do
      {Money.Currency.name!(currency), currency}
    end
  end

  defp list_clients do
    Directory.list_contacts()
    |> Enum.map(&{&1.name, &1.nif})
  end

  defp list_payment_methods(nif) do
    Book.list_payment_methods(nif)
    |> Enum.map(&{&1.name, &1.slug})
  end

  defp list_templates(nif) do
    Book.list_templates(nif)
    |> Enum.map(& &1.name)
  end

  defp list_countries do
    #  TODO priorise most used contries first
    for country <- Countries.all() do
      #  TODO add i18n (see :countries_i18n)
      {country.name, country.alpha2}
    end
  end

  @impl true
  def update(%{create_invoice: invoice} = assigns, socket) do
    changeset = SetInvoice.changeset(invoice, %{action: :insert})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(params: %{"nif" => assigns.company_nif})
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"create_invoice" => invoice_params}, socket) do
    validate(socket, invoice_params)
  end

  def handle_event("save", %{"create_invoice" => invoice_params}, socket) do
    save_invoice(socket, socket.assigns.action, invoice_params)
  end

  def handle_event("del_detail", %{"index" => index}, socket) do
    socket.assigns.params
    |> Map.put_new("details", %{})
    |> Map.update!("details", &del_detail(index, &1))
    |> then(&validate(socket, &1))
  end

  def handle_event("add_detail", %{}, socket) do
    socket.assigns.params
    |> Map.put_new("details", %{})
    |> Map.update!("details", &add_new_detail/1)
    |> then(&validate(socket, &1))
  end

  defp del_detail(_index, nil), do: %{}

  defp del_detail(index, details) do
    details
    |> Map.delete(index)
    |> reenumerate()
  end

  defp add_new_detail(nil), do: %{"0" => new_detail()}

  defp add_new_detail(details) when is_map(details) do
    details
    |> Map.put_new("new", new_detail())
    |> reenumerate()
  end

  defp reenumerate(details) do
    details
    |> Enum.map(fn {_, detail} -> detail end)
    |> Enum.with_index(&{to_string(&2), &1})
    |> Map.new()
  end

  defp new_detail do
    %{
      "sku" => "",
      "description" => "",
      "tax" => "",
      "base_price" => "",
      "units" => "1",
      "tax_price" => "",
      "total_price" => ""
    }
  end

  defp get_client_country(nil), do: nil

  defp get_client_country(nif) do
    if client = Directory.get_contact(nif) do
      client.country
    end
  end

  defp validate(socket, invoice_params) do
    destination_country = invoice_params["destination_country"]
    country = get_client_country(invoice_params["client_nif"]) || destination_country

    invoice_params =
      invoice_params
      |> Map.put("destination_country", country)
      |> Map.put("nif", socket.assigns.company_nif)

    changeset =
      socket.assigns.create_invoice
      |> SetInvoice.changeset(invoice_params)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign_form(changeset)
      |> assign(params: invoice_params)

    {:noreply, socket}
  end

  defp save_invoice(socket, :edit, invoice_params) do
    changeset = SetInvoice.changeset(socket.assigns.modify_invoice, invoice_params)

    if changeset.valid? and dispatch(SetInvoice.to_command(changeset)) == :ok do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Invoice modified successfully"))
       |> push_patch(to: socket.assigns.patch)}
    else
      Logger.debug("changeset errors: #{inspect(changeset.erorrs)}")
      changeset = Map.put(changeset, :action, :validate)
      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_invoice(socket, :new, invoice_params) do
    changeset = SetInvoice.changeset(socket.assigns.create_invoice, invoice_params)

    if changeset.valid? and dispatch(SetInvoice.to_command(changeset)) == :ok do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Invoice created successfully"))
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
