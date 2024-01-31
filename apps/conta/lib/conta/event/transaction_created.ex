defmodule Conta.Event.TransactionCreated do
  @derive Jason.Encoder
  defstruct [:id, :ledger, :on_date, entries: []]
end
