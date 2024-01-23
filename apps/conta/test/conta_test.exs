defmodule ContaTest do
  use ExUnit.Case

  describe "ledger create account execute" do
    test "create account successful" do
      command =
        %Conta.Command.CreateAccount{
          name: ["Assets"],
          type: :assets,
          currency: :EUR,
          notes: nil,
          ledger: "default"
        }

      ledger = %Conta.Aggregate.Ledger{name: "default"}
      event = Conta.Aggregate.Ledger.execute(ledger, command)

      assert %Conta.Event.AccountCreated{
        name: ["Assets"],
        type: :assets,
        currency: :EUR,
        notes: nil,
        ledger: "default"
      } = event

      ledger = Conta.Aggregate.Ledger.apply(ledger, event)

      assert %Conta.Aggregate.Ledger{
        name: "default",
        accounts: %{
          ["Assets"] => %Conta.Aggregate.Ledger.Account{
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
        %Conta.Command.CreateAccount{
          name: ["NonExist", "Child"],
          type: :assets,
          currency: :EUR,
          notes: nil,
          ledger: "default"
        }

      ledger = %Conta.Aggregate.Ledger{name: "default"}
      assert {:error, :invalid_parent_account} = Conta.Aggregate.Ledger.execute(ledger, command)
    end
  end
end
