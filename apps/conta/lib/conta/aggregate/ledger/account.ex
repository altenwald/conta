defmodule Conta.Aggregate.Ledger.Account do
  @type account_type() :: :income | :outcome | :active | :passive
  defstruct [:name, :type, :currency, :notes, balances: %{}]
end
