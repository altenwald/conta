defmodule ContaWeb.InvoiceHTML do
  use ContaWeb, :html

  embed_templates "invoice_html/*"

  defp get_logo(nil, _invoice_id, _embedded, nil), do: "/images/logo.png"
  defp get_logo(base_path, _invoice_id, _embedded, nil), do: "#{base_path}/static/images/logo.png"

  defp get_logo(_, _invoice_id, true, template) do
    data = Base.encode64(template.logo)
    "data:#{template.logo_mime_type};base64,#{data}"
  end

  defp get_logo(_, invoice_id, _embedded, _template) do
    ~p"/books/invoices/#{invoice_id}/logo"
  end
end
