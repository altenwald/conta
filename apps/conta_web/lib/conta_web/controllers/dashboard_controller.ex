defmodule ContaWeb.DashboardController do
  use ContaWeb, :controller
  import Conta.MoneyHelpers

  def image(conn, %{"type" => type, "currency" => currency} = params) do
    with true <- type in ~w[outcome income pnl patrimony banks bank],
         true <- is_currency(currency) do
      theme = parse_theme(params["theme"])

      svg =
        chart(type, String.to_existing_atom(currency))
        |> Plotto.to_svg!()
        |> Conta.Stats.inject_theme_style(theme)

      conn
      |> put_resp_content_type("image/svg+xml")
      |> send_resp(200, svg)
    else
      false ->
        conn
        |> put_status(:not_found)
        |> html("Not found")
    end
  end

  defp parse_theme("dark"), do: :dark
  defp parse_theme("light"), do: :light
  defp parse_theme(_), do: :system

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

  defp chart("banks", currency) do
    Conta.Stats.chart_banks(currency, 12)
  end

  defp chart("bank", currency) do
    Conta.Stats.chart_banks(currency, 12)
  end
end
