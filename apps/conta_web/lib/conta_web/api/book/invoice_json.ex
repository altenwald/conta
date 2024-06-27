defmodule ContaWeb.Api.Book.InvoiceJSON do
  import Conta.MoneyHelpers

  def index(%{invoices: invoices, extended: true}) do
    invoices
  end

  def index(%{invoices: invoices, extended: false}) do
    Enum.map(invoices, &data/1)
  end

  defp data(invoice) do
    %{
      "invoice_number" => invoice.invoice_number,
      "invoice_date" => invoice.invoice_date,
      "paid_date" => invoice.paid_date,
      "client_name" => if(invoice.client, do: invoice.client.name),
      "destination_country" => invoice.destination_country,
      "subtotal_price" => to_money(invoice.subtotal_price) |> Money.to_decimal(),
      "tax_price" => to_money(invoice.tax_price) |> Money.to_decimal(),
      "total_price" => to_money(invoice.total_price) |> Money.to_decimal(),
      "currency" => invoice.currency
    }
  end
end
