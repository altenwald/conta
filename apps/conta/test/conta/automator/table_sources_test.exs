defmodule Conta.Automator.TableSourcesTest do
  use Conta.DataCase
  import Conta.BookFixtures

  alias Conta.Automator.TableSources
  alias Conta.Projector.Book.Expense

  describe "names/0 and options/0" do
    test "expose the two known sources" do
      assert TableSources.names() == ["expenses", "invoices"]
      assert TableSources.options() == [{"Expenses", "expenses"}, {"Invoices", "invoices"}]
    end
  end

  describe "known?/1" do
    test "true for a registered source" do
      assert TableSources.known?("expenses")
    end

    test "false for anything else" do
      refute TableSources.known?("gastos")
    end
  end

  describe "expenses_key/0, invoices_key/0, default_sample_limit/0" do
    test "expose the canonical keys and default" do
      assert TableSources.expenses_key() == "expenses"
      assert TableSources.invoices_key() == "invoices"
      assert TableSources.default_sample_limit() == 5
    end
  end

  describe "sample/2" do
    test "returns up to `limit` real invoices for the invoices source" do
      insert(:invoice, %{invoice_number: "2023-00001"})
      insert(:invoice, %{invoice_number: "2023-00002"})

      assert length(TableSources.sample("invoices", 1)) == 1
    end

    test "returns up to `limit` real expenses for the expenses source" do
      Repo.insert!(%Expense{
        name: "Office supplies",
        invoice_number: "EXP-001",
        invoice_date: ~D[2024-01-15],
        currency: :EUR
      })

      Repo.insert!(%Expense{
        name: "Travel",
        invoice_number: "EXP-002",
        invoice_date: ~D[2024-02-15],
        currency: :EUR
      })

      assert length(TableSources.sample("expenses", 1)) == 1
    end

    test "returns an error tuple for an unknown source" do
      assert TableSources.sample("gastos", 5) == {:error, :unknown_source}
    end
  end
end
