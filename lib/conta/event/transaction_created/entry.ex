defmodule Conta.Event.TransactionCreated.Entry do
  @derive Jason.Encoder
  defstruct [
    description: nil,
    account_name: nil,
    credit: 0,
    debit: 0,
    balance: 0,
    currency: :EUR,
    change_currency: :EUR,
    change_credit: 0,
    change_debit: 0,
    change_price: 1.0
  ]
end
