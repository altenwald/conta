defmodule Conta.Automator.TableSources do
  @moduledoc """
  Registry of the real data sources available for a `:table` parameter of
  a Filter/Shortcut. Backs the canonical param-name keys used by the export
  controllers (`ContaWeb.ExpenseController`, `ContaWeb.InvoiceController`),
  and is intended to also back the "Load real data" button of the test-run
  panel and the restricted name select of the parameter-definition form.
  """

  alias Conta.Book

  @expenses_key "expenses"
  @invoices_key "invoices"
  @default_sample_limit 5

  @labels %{
    @expenses_key => "Expenses",
    @invoices_key => "Invoices"
  }

  @spec expenses_key() :: String.t()
  def expenses_key, do: @expenses_key

  @spec invoices_key() :: String.t()
  def invoices_key, do: @invoices_key

  @spec default_sample_limit() :: pos_integer()
  def default_sample_limit, do: @default_sample_limit

  @spec names() :: [String.t()]
  def names, do: [@expenses_key, @invoices_key]

  @spec options() :: [{String.t(), String.t()}]
  def options, do: Enum.map(names(), fn name -> {@labels[name], name} end)

  @spec known?(String.t()) :: boolean()
  def known?(name), do: Map.has_key?(@labels, name)

  @spec sample(String.t(), pos_integer()) :: [struct()] | {:error, :unknown_source}
  def sample(@expenses_key, limit), do: Book.list_simple_expenses_filtered([], limit)
  def sample(@invoices_key, limit), do: Book.list_invoices_filtered([], limit)
  def sample(_name, _limit), do: {:error, :unknown_source}
end
