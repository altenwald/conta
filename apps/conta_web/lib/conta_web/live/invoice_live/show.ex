defmodule ContaWeb.InvoiceLive.Show do
  use ContaWeb, :live_view

  alias Conta.Book

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket, layout: {ContaWeb.Layouts, :print}}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    invoice = Book.get_invoice!(id)
    template = Book.get_template_by_name!(invoice.company.nif, invoice.template)

    {:noreply,
     socket
     |> assign(:page_title, invoice.invoice_number)
     |> assign(:invoice, invoice)
     |> assign(:template, template)}
  end

  defp get_logo(nil, nil), do: "/images/logo.png"
  defp get_logo(base_path, nil), do: "#{base_path}/static/images/logo.png"

  defp get_logo(_, template) do
    data = Base.encode64(template.logo)
    "data:#{template.logo_mime_type};base64,#{data}"
  end
end
