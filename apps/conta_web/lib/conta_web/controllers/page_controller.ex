defmodule ContaWeb.PageController do
  use ContaWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
