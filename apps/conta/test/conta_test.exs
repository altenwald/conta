defmodule ContaTest do
  use ExUnit.Case
  alias Conta.Aggregate.Ledger
  alias Conta.Command.AccountTransaction
  alias Conta.Command.CreateAccount
  alias Conta.Event.AccountCreated
  alias Conta.Event.TransactionCreated

  describe "ledger create account execute" do
    test "create account successful" do
      command =
        %CreateAccount{
          name: ["Assets"],
          type: :assets,
          currency: :EUR,
          notes: nil,
          ledger: "default"
        }

      ledger = %Ledger{name: "default"}
      event = Ledger.execute(ledger, command)

      assert %AccountCreated{
        name: ["Assets"],
        type: :assets,
        currency: :EUR,
        notes: nil,
        ledger: "default"
      } = event

      ledger = Ledger.apply(ledger, event)

      assert %Ledger{
        name: "default",
        accounts: %{
          ["Assets"] => %Ledger.Account{
            name: ["Assets"],
            type: :assets,
            currency: :EUR,
            notes: nil,
            balances: %{}
          }
        }
      } = ledger
    end

    test "create account failure" do
      command =
        %CreateAccount{
          name: ["NonExist", "Child"],
          type: :assets,
          currency: :EUR,
          notes: nil,
          ledger: "default"
        }

      ledger = %Ledger{name: "default"}
      assert {:error, :invalid_parent_account} = Ledger.execute(ledger, command)
    end
  end

  describe "ledger create transaction execute" do
    test "create transaction successful" do
      command =
        %AccountTransaction{
          ledger: "default",
          on_date: ~D[2024-01-31],
          entries: [
            %AccountTransaction.Entry{
              description: "Albert Heijn",
              account_name: ["Assets", "Cash"],
              credit: 500,
              debit: 0
            },
            %AccountTransaction.Entry{
              description: "Albert Heijn",
              account_name: ["Expenses", "Supermarket"],
              credit: 0,
              debit: 5_00
            }
          ]
        }

      ledger =
        %Ledger{
          name: "default",
          accounts: %{
            ["Assets"] => %Ledger.Account{
              name: ["Assets"],
              type: :assets,
              currency: :EUR,
              balances: %{EUR: 100_00, USD: 100_00}
            },
            ["Assets", "Cash"] => %Ledger.Account{
              name: ["Assets", "Cash"],
              type: :assets,
              currency: :EUR,
              balances: %{EUR: 100_00}
            },
            ["Assets", "PayPal"] => %Ledger.Account{
              name: ["Assets", "PayPal"],
              type: :assets,
              currency: :USD,
              balances: %{USD: 100_00}
            },
            ["Expenses"] => %Ledger.Account{
              name: ["Expenses"],
              type: :expenses,
              currency: :EUR,
              balances: %{EUR: 50_00}
            },
            ["Expenses", "Supermarket"] => %Ledger.Account{
              name: ["Expenses", "Supermarket"],
              type: :expenses,
              currency: :EUR,
              balances: %{EUR: 50_00}
            }
          }
        }
      event = Ledger.execute(ledger, command)

      assert %TransactionCreated{
        id: _,
        ledger: "default",
        on_date: ~D[2024-01-31],
        entries: [
          %TransactionCreated.Entry{
            account_name: ["Assets", "Cash"],
            description: "Albert Heijn",
            balance: 95_00,
            credit: 5_00
          },
          %TransactionCreated.Entry{
            account_name: ["Expenses", "Supermarket"],
            description: "Albert Heijn",
            balance: 55_00,
            debit: 5_00
          }
        ]
      } = event

      ledger = Ledger.apply(ledger, event)

      assert %Ledger{
        name: "default",
        accounts: %{
          ["Assets"] => %Ledger.Account{
            name: ["Assets"],
            type: :assets,
            currency: :EUR,
            balances: %{EUR: 95_00, USD: 100_00}
          },
          ["Assets", "Cash"] => %Ledger.Account{
            name: ["Assets", "Cash"],
            type: :assets,
            currency: :EUR,
            balances: %{EUR: 95_00}
          },
          ["Assets", "PayPal"] => %Ledger.Account{
            name: ["Assets", "PayPal"],
            type: :assets,
            currency: :USD,
            balances: %{USD: 100_00}
          },
          ["Expenses"] => %Ledger.Account{
            name: ["Expenses"],
            type: :expenses,
            currency: :EUR,
            balances: %{EUR: 55_00}
          },
          ["Expenses", "Supermarket"] => %Ledger.Account{
            name: ["Expenses", "Supermarket"],
            type: :expenses,
            currency: :EUR,
            balances: %{EUR: 55_00}
          }
        }
      } == ledger
    end
  end
end
