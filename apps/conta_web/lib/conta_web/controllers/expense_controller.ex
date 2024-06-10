defmodule ContaWeb.ExpenseController do
  use ContaWeb, :controller
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
end
