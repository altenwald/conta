defmodule ContaWeb.InvoiceController do
  use ContaWeb, :controller

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

  def download(conn, %{"id" => id}) do
    invoice = Book.get_invoice!(id)
    template = Book.get_template_by_name!(invoice.company.nif, invoice.template)

    content_opts = %{
      view_module: ContaWeb.InvoiceView,
      view_template: "show.html",
      invoice: invoice,
      template: template
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

    {:ok, pdf} = ChromicPDF.print_to_pdf({:html, html})

    conn
    |> put_resp_content_type("application/pdf")
    |> put_resp_header(
      "content-disposition",
      "attachment; filename=#{invoice.invoice_number}.pdf"
    )
    |> send_resp(200, Base.decode64!(pdf))
  end
end
