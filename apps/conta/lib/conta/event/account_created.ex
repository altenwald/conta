defmodule Conta.Event.AccountCreated do
  @derive Jason.Encoder
  defstruct [:name, :type, :currency, :ledger, :notes]
end
