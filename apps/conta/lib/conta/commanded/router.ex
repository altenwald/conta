defmodule Conta.Commanded.Router do
  use Commanded.Commands.Router

  alias Conta.Aggregate.Company
  alias Conta.Aggregate.Ledger

  alias Conta.Command.RemoveAccountTransaction
  alias Conta.Command.RemoveExpense
  alias Conta.Command.RemoveInvoice
  alias Conta.Command.SetAccount
  alias Conta.Command.SetAccountTransaction
  alias Conta.Command.SetCompany
  alias Conta.Command.SetContact
  alias Conta.Command.SetExpense
  alias Conta.Command.SetInvoice
  alias Conta.Command.SetPaymentMethod
  alias Conta.Command.SetShortcut
  alias Conta.Command.SetTemplate

  identify(Ledger, by: :ledger)

  dispatch(RemoveAccountTransaction, to: Ledger)
  dispatch(SetAccountTransaction, to: Ledger)
  dispatch(SetAccount, to: Ledger)
  dispatch(SetShortcut, to: Ledger)

  dispatch(RemoveExpense, to: Company, identity: :nif)
  dispatch(RemoveInvoice, to: Company, identity: :nif)
  dispatch(SetExpense, to: Company, identity: :nif)
  dispatch(SetInvoice, to: Company, identity: :nif)
  dispatch(SetCompany, to: Company, identity: :nif)
  dispatch(SetContact, to: Company, identity: :company_nif)
  dispatch(SetPaymentMethod, to: Company, identity: :nif)
  dispatch(SetTemplate, to: Company, identity: :nif)
end
