defmodule Conta.Commanded.Router do
  use Commanded.Commands.Router

  alias Conta.Aggregate.Company
  alias Conta.Aggregate.Ledger
  alias Conta.Command.AccountTransaction
  alias Conta.Command.SetAccount
  alias Conta.Command.CreateInvoice
  alias Conta.Command.SetCompany
  alias Conta.Command.SetShortcut
  alias Conta.Command.SetTemplate

  identify(Ledger, by: :ledger)

  dispatch(AccountTransaction, to: Ledger)
  dispatch(SetAccount, to: Ledger)
  dispatch(SetShortcut, to: Ledger)

  identify(Company, by: :nif)

  dispatch(SetCompany, to: Company)
  dispatch(SetTemplate, to: Company)
  dispatch(CreateInvoice, to: Company)
end
