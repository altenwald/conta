defmodule ContaWeb.Api.Book.ExpenseJSON do
  import Conta.MoneyHelpers

  def index(%{expenses: expenses, extended: true}) do
    expenses
  end

  def index(%{expenses: expenses, extended: false}) do
    Enum.map(expenses, &data/1)
  end

  defp data(expense) do
    %{
      "invoice_number" => expense.invoice_number,
      "invoice_date" => expense.invoice_date,
      "provider_name" => expense.provider.name,
      "subtotal_price" => to_money(expense.subtotal_price) |> Money.to_decimal(),
      "tax_price" => to_money(expense.tax_price) |> Money.to_decimal(),
      "total_price" => to_money(expense.total_price) |> Money.to_decimal(),
      "currency" => expense.currency
    }
  end
end
