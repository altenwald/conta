defmodule ContaWeb.DashboardController do
  use ContaWeb, :controller
  import Conta.MoneyHelpers

  def image(conn, %{"type" => type, "currency" => currency}) do
    with true <- type in ~w[outcome income pnl patrimony],
         true <- is_currency(currency) do
      image =
        svg(type, String.to_existing_atom(currency))
        |> to_png()

      conn
      |> put_resp_content_type("image/png")
      |> send_resp(200, image)
    else
      false ->
        conn
        |> put_status(:not_found)
        |> html("Not found")
    end
  end

  defp svg("patrimony", currency) do
    Conta.Stats.graph_patrimony(currency) |> to_string()
  end

  defp svg("outcome", currency) do
    Conta.Stats.graph_outcome(currency) |> to_string()
  end

  defp svg("income", currency) do
    Conta.Stats.graph_income(currency) |> to_string()
  end

  defp svg("pnl", currency) do
    Conta.Stats.graph_pnl(currency, 6) |> to_string()
  end

  defp to_png(graph) when is_binary(graph) do
    {:ok, png} = Resvg.svg_string_to_png_buffer(graph, resources_dir: "/tmp")
    png
  end
end
