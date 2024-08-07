defmodule Conta.Commanded.Router do
  use Commanded.Commands.Router

  alias Conta.Aggregate.Automator
  alias Conta.Aggregate.Company
  alias Conta.Aggregate.Ledger

  alias Conta.Command.RemoveAccount
  alias Conta.Command.RemoveAccountTransaction
  alias Conta.Command.RemoveContact
  alias Conta.Command.RemoveExpense
  alias Conta.Command.RemoveFilter
  alias Conta.Command.RemoveInvoice
  alias Conta.Command.RemoveShortcut
  alias Conta.Command.SetAccount
  alias Conta.Command.SetAccountTransaction
  alias Conta.Command.SetCompany
  alias Conta.Command.SetContact
  alias Conta.Command.SetExpense
  alias Conta.Command.SetFilter
  alias Conta.Command.SetInvoice
  alias Conta.Command.SetPaymentMethod
  alias Conta.Command.SetShortcut
  alias Conta.Command.SetTemplate

  identify(Automator, by: :automator)

  dispatch(RemoveFilter, to: Automator)
  dispatch(RemoveShortcut, to: Automator)
  dispatch(SetFilter, to: Automator)
  dispatch(SetShortcut, to: Automator)

  identify(Ledger, by: :ledger)

  dispatch(RemoveAccount, to: Ledger)
  dispatch(RemoveAccountTransaction, to: Ledger)
  dispatch(SetAccountTransaction, to: Ledger)
  dispatch(SetAccount, to: Ledger)

  dispatch(RemoveContact, to: Company, identity: :company_nif)
  dispatch(RemoveExpense, to: Company, identity: :nif)
  dispatch(RemoveInvoice, to: Company, identity: :nif)
  dispatch(SetCompany, to: Company, identity: :nif)
  dispatch(SetContact, to: Company, identity: :company_nif)
  dispatch(SetExpense, to: Company, identity: :nif)
  dispatch(SetInvoice, to: Company, identity: :nif)
  dispatch(SetPaymentMethod, to: Company, identity: :nif)
  dispatch(SetTemplate, to: Company, identity: :nif)
end
