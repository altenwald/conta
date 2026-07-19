defmodule Conta.Commanded.Router do
  use Commanded.Commands.Router

  alias Conta.Aggregate.Automator
  alias Conta.Aggregate.Company
  alias Conta.Aggregate.Ledger
  alias Conta.Aggregate.Reconciliation

  alias Conta.Command.ImportMovements
  alias Conta.Command.MarkMovementTransacted
  alias Conta.Command.RemoveAccount
  alias Conta.Command.RemoveAccountTransaction
  alias Conta.Command.RemoveContact
  alias Conta.Command.RemoveExpense
  alias Conta.Command.RemoveFilter
  alias Conta.Command.RemoveImporter
  alias Conta.Command.RemoveInvoice
  alias Conta.Command.RemoveMatchRule
  alias Conta.Command.RemoveMovement
  alias Conta.Command.RemoveShortcut
  alias Conta.Command.ReorderMatchRules
  alias Conta.Command.SetAccount
  alias Conta.Command.SetAccountTransaction
  alias Conta.Command.SetCompany
  alias Conta.Command.SetContact
  alias Conta.Command.SetExpense
  alias Conta.Command.SetFilter
  alias Conta.Command.SetImporter
  alias Conta.Command.SetInvoice
  alias Conta.Command.SetMatchRule
  alias Conta.Command.SetPaymentMethod
  alias Conta.Command.SetShortcut
  alias Conta.Command.SetTemplate
  alias Conta.Command.UpdateMovement

  identify(Automator, by: :automator)

  dispatch(RemoveFilter, to: Automator)
  dispatch(RemoveImporter, to: Automator)
  dispatch(RemoveShortcut, to: Automator)
  dispatch(SetFilter, to: Automator)
  dispatch(SetImporter, to: Automator)
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

  # Reconciliation is a singleton whose commands default their identity field
  # to the literal string "default" - the same raw identity Ledger's commands
  # default to. Without a distinct prefix, Commanded uses that raw identity as
  # the event store's stream_uuid, so both aggregates would read and write
  # the exact same physical stream and replay each other's events (silently
  # discarded today only because both `apply/2` have a catch-all clause).
  # Ledger keeps its unprefixed "default" stream to preserve its existing
  # history; Reconciliation moves to its own "reconciliation-default" stream,
  # which starts empty (its prior events stay behind on the old shared
  # stream, unreachable from here on).
  identify(Reconciliation, by: :reconciliation, prefix: "reconciliation-")

  dispatch(ImportMovements, to: Reconciliation)
  dispatch(MarkMovementTransacted, to: Reconciliation)
  dispatch(RemoveMatchRule, to: Reconciliation)
  dispatch(RemoveMovement, to: Reconciliation)
  dispatch(ReorderMatchRules, to: Reconciliation)
  dispatch(SetMatchRule, to: Reconciliation)
  dispatch(UpdateMovement, to: Reconciliation)
end
