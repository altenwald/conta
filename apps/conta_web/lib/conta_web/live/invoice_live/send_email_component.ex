defmodule ContaWeb.InvoiceLive.SendEmailComponent do
  use ContaWeb, :live_component

  alias Conta.Book
  alias Conta.Directory

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h3 class="font-bold text-lg mb-2">{@title}</h3>
      <p class="text-xs opacity-70 mb-4">
        {gettext("Select the recipient emails and review the message before sending.")}
      </p>

      <div :if={@error_message} class="alert alert-error text-sm mb-4">
        <.icon name="hero-exclamation-triangle" class="w-5 h-5" />
        <span>{@error_message}</span>
      </div>

      <div class="card bg-base-200 border border-base-300 p-4 mb-4">
        <h4 class="text-xs font-bold uppercase tracking-wider opacity-70 mb-2">
          {gettext("Attached Invoices (PDF)")}
        </h4>
        <div class="flex flex-wrap gap-2">
          <div
            :for={invoice <- @invoices}
            class="badge badge-lg gap-2 py-3 bg-base-100 border border-base-300 shadow-sm"
          >
            <.icon name="hero-document-arrow-down" class="w-4 h-4 text-primary" />
            <span class="font-bold font-mono">{invoice.invoice_number}.pdf</span>
            <span class="text-xs opacity-70">
              ({Money.new(invoice.total_price, invoice.currency)})
            </span>
          </div>
        </div>
      </div>

      <form id="send-invoice-email-form" phx-target={@myself} phx-submit="send" class="space-y-4">
        <div>
          <label class="label font-bold text-sm">
            <span class="label-text">{gettext("Recipients")}</span>
          </label>

          <div class="space-y-2 bg-base-100 p-3 rounded-lg border border-base-300">
            <div :for={{email, checked} <- @client_emails_state} class="form-control">
              <label class="cursor-pointer label justify-start gap-3 py-1">
                <input
                  type="checkbox"
                  name={"email_toggle[#{email}]"}
                  checked={checked}
                  phx-click="toggle_email"
                  phx-value-email={email}
                  phx-target={@myself}
                  class="checkbox checkbox-primary checkbox-sm"
                />
                <span class="label-text font-mono text-sm">{email}</span>
                <span :if={email in @client_emails} class="badge badge-xs badge-info opacity-70">
                  {gettext("Client")}
                </span>
              </label>
            </div>

            <div :if={@client_emails_state == %{}} class="text-xs text-warning py-1">
              <.icon name="hero-exclamation-circle" class="w-4 h-4 inline mr-1" />
              {gettext("No client emails registered in the directory. You can add one below.")}
            </div>

            <div :if={@company_email} class="divider my-1"></div>

            <div :if={@company_email} class="form-control">
              <label class="cursor-pointer label justify-start gap-3 py-1">
                <input
                  type="checkbox"
                  name={"email_toggle[#{@company_email}]"}
                  checked={@company_email_checked}
                  phx-click="toggle_company_email"
                  phx-target={@myself}
                  class="checkbox checkbox-secondary checkbox-sm"
                />
                <span class="label-text font-mono text-sm">{@company_email}</span>
                <span class="badge badge-xs badge-ghost opacity-70">
                  {gettext("Company (Copy)")}
                </span>
              </label>
            </div>
          </div>
        </div>

        <div>
          <label class="label py-1">
            <span class="label-text font-bold text-xs opacity-70">
              {gettext("Add another recipient email")}
            </span>
          </label>
          <div class="join w-full">
            <label class="input input-bordered join-item flex items-center gap-2 flex-grow">
              <.icon name="hero-envelope" class="w-4 h-4 opacity-50" />
              <input
                type="email"
                name="new_recipient"
                value={@new_recipient}
                placeholder="other@client.com"
                class="grow"
                phx-change="update_new_recipient"
                phx-target={@myself}
              />
            </label>
            <button
              type="button"
              phx-click="add_recipient"
              phx-target={@myself}
              class="btn btn-outline join-item"
            >
              <.icon name="hero-plus" class="w-4 h-4 mr-1" />
              {gettext("Add")}
            </button>
          </div>
        </div>

        <div>
          <.input
            type="text"
            name="subject"
            value={@subject}
            label={gettext("Subject")}
            phx-change="update_subject"
            phx-target={@myself}
            required
          />
        </div>

        <div>
          <.input
            type="textarea"
            name="body"
            value={@body}
            label={gettext("Message Body")}
            rows="6"
            phx-change="update_body"
            phx-target={@myself}
            required
          />
        </div>

        <div class="flex justify-end gap-2 pt-2">
          <.link class="btn btn-ghost" patch={@patch}>
            {gettext("Cancel")}
          </.link>
          <button
            type="submit"
            class={["btn btn-primary", not @has_recipients? && "btn-disabled"]}
            disabled={not @has_recipients?}
            phx-disable-with={gettext("Sending...")}
          >
            <.icon name="hero-paper-airplane" class="w-5 h-5 mr-1" />
            {gettext("Send")}
          </button>
        </div>
      </form>
    </div>
    """
  end

  @impl true
  def update(%{invoices: invoices} = assigns, socket) do
    first_invoice = hd(invoices)
    company_nif = first_invoice.company.nif
    client_emails = get_client_emails(company_nif, first_invoice.client)
    company_email = first_invoice.company.email || Application.get_env(:conta, :mailer_from)

    client_emails_state = Map.new(client_emails, fn email -> {email, true} end)
    subject = build_default_subject(invoices, first_invoice)
    body = build_default_body(invoices, first_invoice)
    has_recipients? = has_selected_recipients?(client_emails_state, company_email, false)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:first_invoice, first_invoice)
     |> assign(:client_emails, client_emails)
     |> assign(:client_emails_state, client_emails_state)
     |> assign(:company_email, company_email)
     |> assign(:company_email_checked, false)
     |> assign(:has_recipients?, has_recipients?)
     |> assign(:new_recipient, "")
     |> assign(:subject, subject)
     |> assign(:body, body)
     |> assign(:error_message, nil)}
  end

  @impl true
  def handle_event("toggle_email", %{"email" => email}, socket) do
    state = socket.assigns.client_emails_state
    new_state = Map.update(state, email, false, fn current -> not current end)

    has_recipients? =
      has_selected_recipients?(
        new_state,
        socket.assigns.company_email,
        socket.assigns.company_email_checked
      )

    {:noreply,
     socket
     |> assign(:client_emails_state, new_state)
     |> assign(:has_recipients?, has_recipients?)}
  end

  def handle_event("toggle_company_email", _params, socket) do
    new_checked = not socket.assigns.company_email_checked

    has_recipients? =
      has_selected_recipients?(
        socket.assigns.client_emails_state,
        socket.assigns.company_email,
        new_checked
      )

    {:noreply,
     socket
     |> assign(:company_email_checked, new_checked)
     |> assign(:has_recipients?, has_recipients?)}
  end

  def handle_event("update_new_recipient", %{"new_recipient" => value}, socket) do
    {:noreply, assign(socket, :new_recipient, value)}
  end

  def handle_event("update_subject", %{"subject" => value}, socket) do
    {:noreply, assign(socket, :subject, value)}
  end

  def handle_event("update_body", %{"body" => value}, socket) do
    {:noreply, assign(socket, :body, value)}
  end

  def handle_event("add_recipient", _params, socket) do
    recipient = String.trim(socket.assigns.new_recipient)

    if recipient =~ ~r/^[^\s]+@[^\s]+$/ do
      state = Map.put(socket.assigns.client_emails_state, recipient, true)

      has_recipients? =
        has_selected_recipients?(
          state,
          socket.assigns.company_email,
          socket.assigns.company_email_checked
        )

      {:noreply,
       socket
       |> assign(:client_emails_state, state)
       |> assign(:new_recipient, "")
       |> assign(:has_recipients?, has_recipients?)
       |> assign(:error_message, nil)}
    else
      {:noreply, assign(socket, :error_message, gettext("Please enter a valid email address"))}
    end
  end

  def handle_event("send", params, socket) do
    subject = params["subject"] || socket.assigns.subject
    body = params["body"] || socket.assigns.body

    recipients = collect_recipients(socket.assigns)

    if recipients == [] do
      {:noreply, assign(socket, :error_message, gettext("Please select at least one recipient email."))}
    else
      deliver_invoices(socket, recipients, subject, body)
    end
  end

  defp deliver_invoices(socket, recipients, subject, body) do
    invoices = socket.assigns.invoices

    attachments =
      Enum.map(invoices, fn inv ->
        template =
          Book.get_template_by_name(inv.company.nif, inv.template) ||
            %Conta.Projector.Book.Template{
              name: inv.template || "default",
              css: "",
              logo: nil,
              logo_mime_type: nil
            }

        {:ok, pdf_data} = ContaWeb.InvoiceController.to_pdf(inv, template)
        {"#{inv.invoice_number}.pdf", "application/pdf", pdf_data}
      end)

    results =
      Enum.map(recipients, fn email ->
        Book.send_invoices_email(invoices, email, %{subject: subject, body: body}, attachments)
      end)

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      {:noreply,
       socket
       |> put_flash(
         :info,
         gettext("Invoices sent by email successfully to %{recipients}",
           recipients: Enum.join(recipients, ", ")
         )
       )
       |> push_patch(to: socket.assigns.patch)}
    else
      {:noreply, assign(socket, :error_message, gettext("There was an error delivering the emails."))}
    end
  end

  defp collect_recipients(assigns) do
    client_recipients =
      assigns.client_emails_state
      |> Enum.filter(fn {_email, checked} -> checked end)
      |> Enum.map(fn {email, _} -> email end)

    if assigns.company_email && assigns.company_email_checked do
      client_recipients ++ [assigns.company_email]
    else
      client_recipients
    end
    |> Enum.uniq()
  end

  defp has_selected_recipients?(client_emails_state, company_email, company_email_checked) do
    any_client_checked? = Enum.any?(client_emails_state, fn {_email, checked} -> checked end)
    company_checked? = company_email != nil and company_email != "" and company_email_checked
    any_client_checked? or company_checked?
  end

  defp get_client_emails(company_nif, %{nif: nif} = client) when is_binary(nif) and nif != "" do
    contact = Directory.get_contact_by_nif(company_nif, nif)

    cond do
      contact != nil && is_list(contact.emails) && contact.emails != [] ->
        contact.emails

      client != nil && is_list(client.emails) && client.emails != [] ->
        client.emails

      true ->
        []
    end
  end

  defp get_client_emails(_company_nif, %{emails: emails}) when is_list(emails), do: emails
  defp get_client_emails(_company_nif, _client), do: []

  defp build_default_subject([invoice], first_invoice) do
    company_name = first_invoice.company.name || "Conta"
    "#{gettext("Invoice")} #{invoice.invoice_number} - #{company_name}"
  end

  defp build_default_subject(invoices, first_invoice) do
    company_name = first_invoice.company.name || "Conta"
    numbers = Enum.map_join(invoices, ", ", & &1.invoice_number)
    "#{gettext("Invoices")} #{numbers} - #{company_name}"
  end

  defp build_default_body([invoice], first_invoice) do
    client_name = if(first_invoice.client, do: first_invoice.client.name, else: gettext("Client"))
    company_name = first_invoice.company.name || "Conta"
    total_str = Money.to_string(Money.new(invoice.total_price, invoice.currency))

    """
    Dear #{client_name},

    Please find attached invoice #{invoice.invoice_number} issued on #{invoice.invoice_date} for a total amount of #{total_str}.

    Please let us know if you have any questions.

    Best regards,
    #{company_name}
    """
  end

  defp build_default_body(invoices, first_invoice) do
    client_name = if(first_invoice.client, do: first_invoice.client.name, else: gettext("Client"))
    company_name = first_invoice.company.name || "Conta"

    invoice_lines =
      Enum.map_join(invoices, "\n", fn inv ->
        total_str = Money.to_string(Money.new(inv.total_price, inv.currency))
        "- #{gettext("Invoice")} #{inv.invoice_number} (#{inv.invoice_date}): #{total_str}"
      end)

    """
    Dear #{client_name},

    Please find attached the following invoices:
    #{invoice_lines}

    Please let us know if you have any questions.

    Best regards,
    #{company_name}
    """
  end
end
