defmodule ContaWeb.InvoiceController do
  use ContaWeb, :controller

  require Logger

  alias Conta.Automator
  alias Conta.Book
  alias Phoenix.HTML.Safe, as: HtmlSafe

  def show(conn, %{"id" => id}) do
    invoice = Book.get_invoice!(id)
    template = Book.get_template_by_name!(invoice.company.nif, invoice.template)

    conn
    |> put_layout(html: {ContaWeb.Layouts, :print})
    |> assign(:page_title, invoice.invoice_number)
    |> assign(:invoice, invoice)
    |> assign(:template, template)
    |> render(:show)
  end

  def to_pdf(invoice, template) do
    content_opts = %{
      view_module: ContaWeb.InvoiceView,
      view_template: "show.html",
      invoice: invoice,
      template: template,
      embedded: true
    }

    layout_opts = %{
      view_module: ContaWeb.Layouts,
      view_template: "root_print.html",
      page_title: invoice.invoice_number,
      inner_content: ContaWeb.InvoiceHTML.show(content_opts),
      invoice: invoice
    }

    html =
      layout_opts
      |> ContaWeb.Layouts.root_print()
      |> HtmlSafe.to_iodata()
      |> to_string()

    ChromicPDF.print_to_pdf({:html, html})
  end

  def download(conn, %{"id" => id}) do
    invoice = Book.get_invoice!(id)
    template = Book.get_template_by_name!(invoice.company.nif, invoice.template)

    {:ok, pdf} = to_pdf(invoice, template)

    conn
    |> put_resp_content_type("application/pdf")
    |> put_resp_header(
      "content-disposition",
      "attachment; filename=#{invoice.invoice_number}.pdf"
    )
    |> send_resp(200, Base.decode64!(pdf))
  end

  defp maybe_disposition(conn, nil), do: conn

  defp maybe_disposition(conn, filename) do
    put_resp_header(conn, "content-disposition", "attachment; filename=#{filename}")
  end

  def run(conn, %{"automator_id" => id} = params) do
    filters = Map.delete(params, "automation_id")
    invoices = Book.list_invoices_filtered(filters)
    params = %{"invoices" => invoices}

    with filter when filter != nil <- Automator.get_filter(id),
         params = Map.new(Automator.cast(filter, params)),
         {:ok, {mimetype, file, content}} <-
           Automator.run_filter(filter.automator, filter, params) do
      conn
      |> put_resp_content_type(mimetype)
      |> maybe_disposition(file)
      |> send_resp(200, content)
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> text("not found")

      {:error, reason} ->
        Logger.error("bad request #{inspect(reason)}")

        conn
        |> put_status(:bad_request)
        |> text("bad request")
    end
  end

  def logo(conn, %{"id" => id}) do
    invoice = Book.get_invoice!(id)
    template = Book.get_template_by_name!(invoice.company.nif, invoice.template)

    conn
    |> put_resp_content_type(template.logo_mime_type)
    |> send_resp(200, template.logo)
  end

  def css(conn, %{"id" => id}) do
    invoice = Book.get_invoice!(id)
    template = Book.get_template_by_name!(invoice.company.nif, invoice.template)

    conn
    |> put_resp_content_type("text/css")
    |> send_resp(200, template.css || "")
  end
end
