defmodule ContaWeb.InvoiceHTML do
  use ContaWeb, :html

  embed_templates "invoice_html/*"

  defp get_logo(nil, _invoice_id, nil), do: "/images/logo.png"
  defp get_logo(base_path, _invoice_id, nil), do: "#{base_path}/static/images/logo.png"

  defp get_logo(_, invoice_id, _template) do
    ~p"/books/invoices/#{invoice_id}/logo"
  end
end
