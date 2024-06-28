defmodule ContaWeb.Api.Book.Expense do
  use ContaWeb, :api

  import Conta.Commanded.Application, only: [dispatch: 1]
  import Conta.EctoHelpers

  alias Conta.Book
  alias Conta.Command.SetExpense

  @expenses_per_page "5"

  def index(conn, %{"term" => term, "year" => year} = params) do
    expenses = Book.list_expenses_by_term_and_year(term, year)
    render(conn, expenses: expenses, extended: params["extended"] == "true")
  end

  def index(conn, params) do
    page = String.to_integer(params["page"] || "1") - 1
    expenses_per_page = String.to_integer(params["page-size"] || @expenses_per_page)
    expenses = Book.list_simple_expenses(expenses_per_page, page * expenses_per_page)
    render(conn, expenses: expenses, extended: params["extended"] == "true")
  end

  def show(conn, %{"id" => id}) do
    if expense = Book.get_expense(id) do
      render(conn, expense: expense)
    else
      conn
      |> put_status(:not_found)
      |> json(%{"errors" => %{"id" => "expense not found"}})
    end
  end

  def delete(conn, %{"id" => id}) do
    with expense when expense != nil <- Book.get_expense(id),
         :ok <- dispatch(Book.get_remove_expense(expense)) do
      json(conn, "ok")
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json("expense not found")

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

  defdelegate download(conn, params), to: ContaWeb.ExpenseController
end
