defmodule Conta.Command.AccountTransaction do
  defstruct [:ledger, :on_date, entries: []]
end
