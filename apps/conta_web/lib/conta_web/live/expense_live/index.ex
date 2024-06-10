defmodule ContaWeb.ExpenseLive.Index do
  use ContaWeb, :live_view

  require Logger

  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Book
  alias Conta.Projector.Book.Expense

  @impl true
  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(Conta.PubSub, "event:expense_set")
    {:ok, stream(socket, :books_expenses, Book.list_simple_expenses())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    set_expense = Book.get_set_expense(id)

    socket
    |> assign(:page_title, gettext("Edit Expense"))
    |> assign(:company_nif, set_expense.nif)
    |> assign(:set_expense, set_expense)
  end

  defp apply_action(socket, :duplicate, %{"id" => id}) do
    set_expense = Book.get_duplicate_expense(id)

    socket
    |> assign(:page_title, gettext("New Expense"))
    |> assign(:company_nif, set_expense.nif)
    |> assign(:set_expense, set_expense)
  end

  defp apply_action(socket, :new, _params) do
    set_expense = Book.new_set_expense()

    socket
    |> assign(:page_title, gettext("New Expense"))
    |> assign(:company_nif, set_expense.nif)
    |> assign(:set_expense, set_expense)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Books Expenses")
    |> assign(:set_expense, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => expense_id, "dom_id" => dom_id}, socket) do
    with %Expense{} = expense <- Book.get_expense(expense_id),
         :ok <- dispatch(Book.get_remove_expense(expense)) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Expense removed successfully"))
       |> stream_delete_by_dom_id(:books_expenses, dom_id)}
    else
      error ->
        Logger.error("cannot remove: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, gettext("Cannot remove the expense"))}
    end
  end

  @impl true
  def handle_info({:expense_set, expense}, socket) do
    Logger.debug(
      "adding expense to the stream #{expense.provider.name} #{expense.invoice_number}"
    )

    {:noreply, stream_insert(socket, :books_expenses, expense, at: 0)}
  end
end
