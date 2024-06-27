defmodule ContaWeb.Api.Book.Invoice do
  use ContaWeb, :api

  import Conta.Commanded.Application, only: [dispatch: 1]
  import Conta.EctoHelpers

  alias Conta.Book
  alias Conta.Command.SetInvoice

  @invoices_per_page "5"

  def index(conn, %{"term" => term, "year" => year} = params) do
    invoices = Book.list_invoices_by_term_and_year(term, year)
    render(conn, invoices: invoices, extended: params["extended"] == "true")
  end

  def index(conn, params) do
    page = String.to_integer(params["page"] || "1") - 1
    invoices_per_page = String.to_integer(params["page-size"] || @invoices_per_page)
    invoices = Book.list_invoices(invoices_per_page, page * invoices_per_page)
    render(conn, invoices: invoices, extended: params["extended"] == "true")
  end

  def show(conn, %{"id" => id}) do
    if invoice = Book.get_invoice(id) do
      render(conn, invoice: invoice)
    else
      conn
      |> put_status(:not_found)
      |> json(%{"errors" => %{"id" => "invoice not found"}})
    end
  end

  def delete(conn, %{"id" => id}) do
    with invoice when invoice != nil <- Book.get_invoice(id),
         :ok <- dispatch(Book.get_remove_invoice(invoice)) do
      json(conn, "ok")
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{"errors" => %{"id" => "invoice not found"}})

      {:error, reason} when is_atom(reason) ->
        conn
        |> put_status(:bad_request)
        |> json(%{"errors" => %{"dispatch" => [reason]}})

      {:error, errors} when is_map(errors) ->
        conn
        |> put_status(:bad_request)
        |> json(%{"errors" => errors})
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
      json(conn, "ok")
    else
      false ->
        {:error, errors} = get_result(changeset)

        conn
        |> put_status(:bad_request)
        |> json(%{"errors" => errors})

      {:error, reason} when is_atom(reason) ->
        conn
        |> put_status(:bad_request)
        |> json(%{"errors" => %{"dispatch" => [reason]}})

      {:error, errors} when is_map(errors) ->
        conn
        |> put_status(:bad_request)
        |> json(%{"errors" => errors})
    end
  end
end
