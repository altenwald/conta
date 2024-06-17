defmodule ContaWeb.Layouts do
  use ContaWeb, :html

  embed_templates "layouts/*"

  def favicon(assigns) do
    ~H"""
    <link rel="apple-touch-icon" sizes="180x180" href={~p"/favicon/apple-touch-icon.png"} />
    <link rel="icon" type="image/png" sizes="32x32" href={~p"/favicon/favicon-32x32.png"} />
    <link rel="icon" type="image/png" sizes="16x16" href={~p"/favicon/favicon-16x16.png"} />
    <link rel="manifest" href={~p"/favicon/site.webmanifest"} />
    <link rel="mask-icon" href={~p"/favicon/safari-pinned-tab.svg"} color="#9e7802" />
    <link rel="shortcut icon" href={~p"/favicon/favicon.ico"} />
    <meta name="apple-mobile-web-app-title" content="Conta" />
    <meta name="application-name" content="Conta" />
    <meta name="msapplication-TileColor" content="#ffc40d" />
    <meta name="msapplication-config" content={~p"/favicon/browserconfig.xml"} />
    <meta name="theme-color" content="#ffffff" />
    """
  end
end
