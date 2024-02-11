defmodule Conta.Aggregate.Ledger.Account do
  @type account_types() :: :assets | :liabilities | :equity | :revenue | :expenses
  defstruct [:id, :name, :type, :currency, :notes, balances: %{}]
end
