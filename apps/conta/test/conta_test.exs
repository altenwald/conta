defmodule ContaTest do
  use ExUnit.Case
  alias Conta.Aggregate.Ledger
  alias Conta.Command.CreateAccount
  alias Conta.Event.AccountCreated

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
end
