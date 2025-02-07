defmodule ContaWeb.ExpenseLive.FormComponent do
  use ContaWeb, :live_component
  import Conta.Commanded.Application, only: [dispatch: 1]
  require Logger

  alias Conta.Book
  alias Conta.Command.SetExpense
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
          <.simple_form for={@form} id="expense-form" phx-target={@myself} phx-change="validate" phx-submit="save">
            <.input field={@form[:nif]} type="text" label={gettext("Company NIF")} disabled="true" />
            <.input field={@form[:name]} type="text" label={gettext("Name")} />
            <.input field={@form[:invoice_number]} type="text" label={gettext("Invoice Number")} />
            <.input field={@form[:invoice_date]} type="date" label={gettext("Invoice Date")} />
            <.input field={@form[:due_date]} type="date" label={gettext("Due Date")} />
            <.input
              field={@form[:category]}
              type="select"
              label={gettext("Category")}
              options={list_categories()}
              prompt={gettext("Choose a category...")}
            />
            <.input
              field={@form[:provider_nif]}
              type="select"
              label={gettext("Provider")}
              options={list_providers()}
              prompt={gettext("Choose a provider...")}
            />
            <.input
              field={@form[:payment_method]}
              type="select"
              label={gettext("Payment Method")}
              options={list_payment_methods(@company_nif)}
              prompt={gettext("Choose a payment method...")}
            />
            <.input
              field={@form[:currency]}
              type="select"
              label={gettext("Currency")}
              options={list_currencies()}
              prompt={gettext("Choose a currency...")}
            />
            <.input field={@form[:subtotal_price]} type="number" step=".01" label={gettext("Subtotal")} />
            <.input field={@form[:tax_price]} type="number" step=".01" label={gettext("Tax Price")} />
            <.input field={@form[:total_price]} type="number" step=".01" label={gettext("Total Price")} />
            <.input
              field={@form[:attachments]}
              type="file"
              upload={@uploads.attachments}
              phx-target={@myself}
              files={@attachments}
              label={gettext("Attachments")}
            />
          </.simple_form>
        </section>
        <footer class="modal-card-foot is-at-right">
          <.button form="expense-form" class="is-primary" phx-disable-with={gettext("Saving...")}>
            <%= gettext("Save Expense") %>
          </.button>
          <.link class="button" patch={~p"/books/expenses"}>
            <%= gettext("Cancel") %>
          </.link>
        </footer>
      </div>
    </div>
    """
  end

  defp list_currencies do
    frequent = Application.get_env(:conta, :frequent_currencies, [])

    currencies =
      Money.Currency.all()
      |> Map.drop(frequent)
      |> Map.keys()

    for currency <- frequent ++ currencies do
      {Money.Currency.name!(currency), currency}
    end
  end

  defp list_categories do
    [
      {gettext("Computers"), "computers"},
      {gettext("Bank fees"), "bank_fees"},
      {gettext("Gasoline"), "gasoline"},
      {gettext("Shipping costs"), "shipping_costs"},
      {gettext("Representation expenses"), "representation_expenses"},
      {gettext("Accounting fees"), "accounting_fees"},
      {gettext("Printing and stationery"), "printing_and_stationery"},
      {gettext("Motor vehicle tax"), "motor_vehicle_tax"},
      {gettext("Professional literature"), "professional_literature"},
      {gettext("Motor vehicle maintenance"), "motor_vehicle_maintenance"},
      {gettext("Office supplies"), "office_supplies"},
      {gettext("Other vehicle costs"), "other_vehicle_costs"},
      {gettext("Other general costs"), "other_general_costs"},
      {gettext("Advertising"), "advertising"},
      {gettext("Vehicle insurances"), "vehicle_insurances"},
      {gettext("General insurances"), "general_insurances"},
      {gettext("Software"), "software"},
      {gettext("Subscriptions"), "subscriptions"},
      {gettext("Phone and internet"), "phone_and_internet"},
      {gettext("Transport"), "transport"},
      {gettext("Travel and accommodation"), "travel_and_accommodation"},
      {gettext("Web hosting or platforms"), "web_hosting_or_platforms"}
    ]
  end

  defp list_providers do
    Directory.list_contacts()
    |> Enum.map(&{&1.name, &1.nif})
  end

  defp list_payment_methods(nif) do
    Book.list_payment_methods(nif)
    |> Enum.map(&{&1.name, &1.slug})
  end

  @impl true
  def update(%{set_expense: expense} = assigns, socket) do
    changeset = SetExpense.changeset(expense, %{action: :insert})

    attachments =
      for attachment <- expense.attachments do
        %{
          "id" => attachment.id,
          "file" => attachment.file,
          "mimetype" => attachment.mimetype,
          "name" => attachment.name,
          "size" => attachment.size
        }
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       params: %{"nif" => assigns.company_nif},
       attachments: attachments,
       expense: expense
     )
     |> allow_upload(:attachments, accept: ~w(.pdf .html), max_entries: 5)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"set_expense" => expense_params}, socket) do
    validate(socket, expense_params)
  end

  def handle_event("save", %{"set_expense" => expense_params}, socket) do
    expense_params =
      consume_uploaded_entries(socket, :attachments, fn %{path: path}, entry ->
        content = File.read!(path)

        {:ok,
         %{
           "file" => content,
           "mimetype" => entry.client_type,
           "name" => entry.client_name,
           "size" => byte_size(content)
         }}
      end)
      |> then(&(&1 ++ socket.assigns.attachments))
      |> Enum.with_index()
      |> Enum.map(fn {data, key} -> {key, data} end)
      |> Map.new()
      |> then(&Map.put(expense_params, "attachments", &1))

    save_expense(socket, socket.assigns.action, expense_params)
  end

  def handle_event("remove", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :attachments, ref)}
  end

  def handle_event("remove", %{"id" => id}, socket) do
    attachments = Enum.reject(socket.assigns.attachments, &(&1["id"] == id))
    {:noreply, assign(socket, :attachments, attachments)}
  end

  defp validate(socket, expense_params) do
    expense_params = Map.put(expense_params, "nif", socket.assigns.company_nif)

    changeset =
      socket.assigns.set_expense
      |> SetExpense.changeset(expense_params)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign_form(changeset)
      |> assign(params: expense_params)

    {:noreply, socket}
  end

  defp save_expense(socket, :edit, expense_params) do
    changeset = SetExpense.changeset(socket.assigns.set_expense, expense_params)

    if changeset.valid? and dispatch(SetExpense.to_command(changeset)) == :ok do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Expense modified successfully"))
       |> push_patch(to: socket.assigns.patch)}
    else
      Logger.debug("changeset errors: #{inspect(changeset.errors)}")
      changeset = Map.put(changeset, :action, :validate)
      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_expense(socket, action, expense_params) when action in [:new, :duplicate] do
    changeset = SetExpense.changeset(socket.assigns.set_expense, expense_params)

    if changeset.valid? and dispatch(SetExpense.to_command(changeset)) == :ok do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Expense created successfully"))
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
