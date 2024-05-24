defmodule ContaBot.Action.Invoice do
  use ContaBot.Action
  alias Conta.Projector.Book.Invoice

  @num_entries 20

  def invoice_output do
    Conta.Book.list_invoices(@num_entries)
    |> Enum.reverse()
    |> Enum.map(fn %Invoice{} = invoice ->
      """
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
  def handle(:init, context) do
    answer(context, invoice_output(), parse_mode: "MarkdownV2")
  end
end
