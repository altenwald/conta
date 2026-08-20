defmodule ContaWeb.DashboardController do
  use ContaWeb, :controller
  import Conta.MoneyHelpers

  def image(conn, %{"type" => type, "currency" => currency}) do
    with true <- type in ~w[outcome income pnl patrimony],
         true <- is_currency(currency) do
      image =
        chart(type, String.to_existing_atom(currency))
        |> Plotto.to_png!()

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

  defp chart("patrimony", currency) do
    Conta.Stats.chart_patrimony(currency)
  end

  defp chart("outcome", currency) do
    Conta.Stats.chart_outcome(currency)
  end

  defp chart("income", currency) do
    Conta.Stats.chart_income(currency)
  end

  defp chart("pnl", currency) do
    Conta.Stats.chart_pnl(currency, 6)
  end
end
