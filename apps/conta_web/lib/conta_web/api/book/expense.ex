defmodule ContaWeb.Api.Book.Expense do
  use ContaWeb, :api

  import Conta.Commanded.Application, only: [dispatch: 1]
  import Conta.EctoHelpers
  import Conta.MoneyHelpers

  alias Conta.Book
  alias Conta.Command.SetExpense

  @expenses_per_page 5

  def index(conn, params) do
    page = String.to_integer(params["page"] || "1") - 1

    expenses =
      Book.list_simple_expenses(@expenses_per_page, page * @expenses_per_page)
      |> Enum.map(
        &%{
          "invoice_number" => &1.invoice_number,
          "invoice_date" => &1.invoice_date,
          "provider_name" => &1.provider.name,
          "subtotal_price" => to_money(&1.subtotal_price) |> Money.to_decimal(),
          "tax_price" => to_money(&1.tax_price) |> Money.to_decimal(),
          "total_price" => to_money(&1.total_price) |> Money.to_decimal(),
          "currency" => &1.currency
        }
      )

    if expenses != [] do
      json(conn, %{
        "page" => page + 1,
        "entities_per_page" => @expenses_per_page,
        "entities" => expenses
      })
    else
      conn
      |> put_status(:not_found)
      |> json(%{"status" => "error", "reason" => "empty page"})
    end
  end

  def show(conn, %{"id" => id}) do
    if expense = Book.get_expense(id) do
      json(conn, %{"status" => "ok", "expense" => expense})
    else
      conn
      |> put_status(:not_found)
      |> json(%{"status" => "error", "reason" => "expense not found"})
    end
  end

  def delete(conn, %{"id" => id}) do
    with expense when expense != nil <- Book.get_expense(id),
         :ok <- dispatch(Book.get_remove_expense(expense)) do
      json(conn, %{"status" => "ok"})
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{"status" => "error", "reason" => "expense not found"})

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
    set_expense(conn, %SetExpense{}, params)
  end

  def update(conn, %{"id" => id} = params) do
    params = Map.put(params, "action", "update")
    set_expense(conn, Book.get_set_expense(id), params)
  end

  defp set_expense(conn, set_expense, params) do
    changeset = SetExpense.changeset(set_expense, params)

    with true <- changeset.valid?,
         :ok <- dispatch(SetExpense.to_command(changeset)) do
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

  defdelegate download(conn, params), to: ContaWeb.ExpenseController
end
