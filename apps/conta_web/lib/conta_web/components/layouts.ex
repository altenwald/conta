defmodule ContaWeb.Layouts do
  use ContaWeb, :html

  embed_templates "layouts/*"

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} title="Success!" flash={@flash} />
      <.flash kind={:error} title="Error!" flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        <div class="flex items-center gap-2">
          <span>{gettext("Attempting to reconnect")}</span>
          <.icon name="hero-arrow-path" class="w-5 h-5 animate-spin" />
        </div>
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={JS.remove_class("close", to: "#server-error")}
        phx-connected={JS.add_class("close", to: "#server-error")}
        hidden
      >
        <div class="flex items-center gap-2">
          <span>{gettext("Hang in there while we get back on track")}</span>
          <.icon name="hero-arrow-path" class="w-5 h-5 animate-spin" />
        </div>
      </.flash>
    </div>
    """
  end

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
