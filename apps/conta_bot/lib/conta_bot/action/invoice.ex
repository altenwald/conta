defmodule ContaBot.Action.Invoice do
  use ContaBot.Action

  alias Conta.Book
  alias Conta.Projector.Book.Invoice
  alias ContaWeb.InvoiceController

  @num_entries 20

  def invoice_output do
    Conta.Book.list_invoices(@num_entries)
    |> Enum.reverse()
    |> Enum.map(fn %Invoice{} = invoice ->
      """
      /i#{String.replace(invoice.invoice_number, "-", "")}
      *#{escape_markdown(invoice.invoice_number)} \\-\\- #{escape_markdown(to_string(invoice.invoice_date))}*
      _#{escape_markdown(format_client(invoice))}_
      ```
      #{currency_fmt(invoice.subtotal_price)} subtotal
      #{currency_fmt(invoice.tax_price)} tax
      #{currency_fmt(invoice.total_price)} total
      ```
      """
    end)
    |> to_string()
    |> case do
      "" -> "No invoices available"
      invoices -> invoices
    end
  end

  defp country(country_code) do
    Countries.get(country_code).name
  end

  defp format_client(%Invoice{client: nil, destination_country: country}) do
    "Client from #{country(country)}"
  end

  defp format_client(%Invoice{client: %Invoice.Client{} = client}) do
    "#{client.name}\n#{client.address}\n#{client.postcode} #{client.city}\n#{country(client.country)}"
  end

  @impl ContaBot.Action
  def handle({:init, "invoice"}, context) do
    match_me(~r"^i[0-9]{9}$")
    answer(context, invoice_output(), parse_mode: "MarkdownV2")
  end

  def handle({:init, <<"i", year::binary-size(4), id::binary-size(5)>>}, context) do
    invoice = Book.get_invoice!(String.to_integer(year), String.to_integer(id))
    template = Book.get_template_by_name!(invoice.company.nif, invoice.template)
    {:ok, encoded_pdf} = InvoiceController.to_pdf(invoice, template)
    pdf = Base.decode64!(encoded_pdf)
    filename = "#{invoice.invoice_number}.pdf"
    ExGram.send_document(get_chat_id(context), {:file_content, pdf, filename})
  end
end
