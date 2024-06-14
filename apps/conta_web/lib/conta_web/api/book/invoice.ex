defmodule ContaWeb.Api.Book.Invoice do
  use ContaWeb, :api

  import Conta.Commanded.Application, only: [dispatch: 1]
  import Conta.EctoHelpers
  import Conta.MoneyHelpers

  alias Conta.Book
  alias Conta.Command.SetInvoice

  @invoices_per_page 5

  def index(conn, params) do
    page = String.to_integer(params["page"] || "1") - 1

    invoices =
      Book.list_invoices(@invoices_per_page, page * @invoices_per_page)
      |> Enum.map(
        &%{
          "invoice_number" => &1.invoice_number,
          "invoice_date" => &1.invoice_date,
          "paid_date" => &1.paid_date,
          "client_name" => if(&1.client, do: &1.client.name),
          "destination_country" => &1.destination_country,
          "subtotal_price" => to_money(&1.subtotal_price) |> Money.to_decimal(),
          "tax_price" => to_money(&1.tax_price) |> Money.to_decimal(),
          "total_price" => to_money(&1.total_price) |> Money.to_decimal(),
          "currency" => &1.currency
        }
      )

    if invoices != [] do
      json(conn, %{
        "page" => page + 1,
        "entities_per_page" => @invoices_per_page,
        "entities" => invoices
      })
    else
      conn
      |> put_status(:not_found)
      |> json(%{"status" => "error", "reason" => "empty page"})
    end
  end

  def show(conn, %{"id" => id}) do
    if invoice = Book.get_invoice(id) do
      json(conn, %{"status" => "ok", "invoice" => invoice})
    else
      conn
      |> put_status(:not_found)
      |> json(%{"status" => "error", "reason" => "invoice not found"})
    end
  end

  def delete(conn, %{"id" => id}) do
    with invoice when invoice != nil <- Book.get_invoice(id),
         :ok <- dispatch(Book.get_remove_invoice(invoice)) do
      json(conn, %{"status" => "ok"})
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{"status" => "error", "reason" => "invoice not found"})

      {:error, reason} when is_atom(reason) ->
        conn
        |> put_status(:bad_request)
        |> json(%{"status" => "error", "errors" => %{"dispatch" => [reason]}})

      {:error, errors} when is_map(errors) ->
        conn
        |> put_status(:bad_request)
        |> json(%{"status" => "error", "errors" => errors})
    end
  end

  def create(conn, params) do
    params = Map.put(params, "action", "insert")
    set_invoice(conn, %SetInvoice{}, params)
  end

  def update(conn, %{"id" => id} = params) do
    params = Map.put(params, "action", "update")
    set_invoice(conn, Book.get_set_invoice(id), params)
  end

  defp set_invoice(conn, set_invoice, params) do
    changeset = SetInvoice.changeset(set_invoice, params)

    with true <- changeset.valid?,
         :ok <- dispatch(SetInvoice.to_command(changeset)) do
      json(conn, %{"status" => "ok"})
    else
      false ->
        {:error, errors} = get_result(changeset)

        conn
        |> put_status(:bad_request)
        |> json(%{"status" => "error", "errors" => errors})

      {:error, reason} when is_atom(reason) ->
        conn
        |> put_status(:bad_request)
        |> json(%{"status" => "error", "errors" => %{"dispatch" => [reason]}})

      {:error, errors} when is_map(errors) ->
        conn
        |> put_status(:bad_request)
        |> json(%{"status" => "error", "errors" => errors})
    end
  end
end
