defmodule Conta do
  import Conta.Commanded.Application
  alias Conta.Command.AccountTransaction
  alias Conta.Command.AccountTransaction.Entry
  alias Conta.Command.CreateAccount

  def create_account(name, type, currency \\ :EUR, notes \\ nil, ledger \\ "default") do
    %CreateAccount{name: name, type: type, currency: currency, notes: notes, ledger: ledger}
    |> dispatch()
  end

  def create_transaction(on_date, entries, ledger \\ "default") do
    %AccountTransaction{ledger: ledger, on_date: on_date, entries: entries}
    |> dispatch()
  end

  def entry(description, account_name, credit, debit, change_currency, change_credit, change_debit, change_price) do
    %Entry{
      description: description,
      account_name: account_name,
      credit: credit,
      debit: debit,
      change_currency: change_currency,
      change_credit: change_credit,
      change_debit: change_debit,
      change_price: change_price
    }
  end
end
