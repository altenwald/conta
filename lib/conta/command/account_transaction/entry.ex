defmodule Conta.Command.AccountTransaction.Entry do
  defstruct [
    description: nil,
    account_name: nil,
    credit: 0,
    debit: 0,
    change_currency: :EUR,
    change_credit: 0,
    change_debit: 0,
    change_price: 1.0
  ]
end
