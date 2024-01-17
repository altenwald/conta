defmodule Conta.Router do
  use Commanded.Commands.Router

  alias Conta.Aggregate.Ledger
  alias Conta.Command.AccountTransaction
  alias Conta.Command.CreateAccount

  identify Ledger, by: :ledger

  dispatch AccountTransaction, to: Ledger
  dispatch CreateAccount, to: Ledger
end
