defmodule ContaWeb.InvoiceHTML do
  use ContaWeb, :html

  embed_templates "invoice_html/*"

  defp get_logo(nil, nil), do: "/images/logo.png"
  defp get_logo(base_path, nil), do: "#{base_path}/static/images/logo.png"

  defp get_logo(_, template) do
    data = Base.encode64(template.logo)
    "data:#{template.logo_mime_type};base64,#{data}"
  end
end
