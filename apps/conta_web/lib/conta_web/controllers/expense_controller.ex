defmodule ContaWeb.ExpenseController do
  use ContaWeb, :controller

  require Logger

  alias Conta.Automator
  alias Conta.Book

  def download(conn, %{"id" => id, "attachment_id" => idx}) do
    idx = String.to_integer(idx) - 1
    attachment = Enum.at(Book.get_expense!(id).attachments, idx)

    conn
    |> put_resp_content_type(attachment.mimetype)
    |> put_resp_header(
      "content-disposition",
      "attachment; filename=#{attachment.name}"
    )
    |> send_resp(200, Base.decode64!(attachment.file))
  end

  defp maybe_disposition(conn, nil), do: conn

  defp maybe_disposition(conn, filename) do
    put_resp_header(conn, "content-disposition", "attachment; filename=#{filename}")
  end

  def run(conn, %{"automator_id" => id} = params) do
    filters = [
      term: params["term"],
      year: params["year"]
    ]

    expenses = Book.list_simple_expenses_filtered(filters)
    params = %{"expenses" => expenses}

    with filter when filter != nil <- Automator.get_filter(id),
         params =
           Automator.cast(filter, params)
           |> Map.new()
           |> Map.put("filename", "expenses.xlsx"),
         {:ok, {mimetype, file, content}} <-
           Automator.run_filter(filter.automator, filter, params) do
      conn
      |> put_resp_content_type(mimetype)
      |> maybe_disposition(file)
      |> send_resp(200, content)
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> text("not found")

      {:error, reason} ->
        Logger.error("bad request #{inspect(reason)}")

        conn
        |> put_status(:bad_request)
        |> text("bad request")
    end
  end
end
