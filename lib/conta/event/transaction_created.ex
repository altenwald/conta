defmodule Conta.Event.TransactionCreated do
  @derive Jason.Encoder
  defstruct [:id, :on_date, entries: []]
end
