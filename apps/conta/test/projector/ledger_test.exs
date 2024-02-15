defmodule Conta.Projector.LedgerTest do
  use Conta.DataCase
  import Conta.Factory
  alias Conta.Projector.Ledger

  setup do
    version =
      if pv = Repo.get(Ledger.ProjectionVersion, "Conta.Projector.Ledger") do
        pv.last_seen_version + 1
      else
        1
      end

    on_exit(fn ->
      Repo.delete_all(Ledger.Entry)
      Repo.delete_all(Ledger.Balance)
      Repo.delete_all(Ledger.Account)
      Repo.delete_all(Ledger.ProjectionVersion)
    end)

    %{
      handler_name: "Conta.Projector.Ledger",
      event_number: version
    }
  end

  describe "account" do
    test "create account", metadata do
      event =
        %Conta.Event.AccountCreated{
          id: "b6ad9e02-0e37-404c-953a-daa8c3d23880",
          name: ["Assets"],
          ledger: "default",
          type: :assets,
          notes: "hello there!"
        }

      assert :ok == Conta.Projector.Ledger.handle(event, metadata)

      assert %Conta.Projector.Ledger.Account{
        id: "b6ad9e02-0e37-404c-953a-daa8c3d23880",
        name: ["Assets"],
        ledger: "default",
        type: :assets,
        notes: "hello there!"
      } = Repo.get!(Conta.Projector.Ledger.Account, "b6ad9e02-0e37-404c-953a-daa8c3d23880")
    end

    test "update account", metadata do
      account = insert(:account, %{name: ["Expenses"], type: :expenses, notes: "global expenses account"})

      event =
        %Conta.Event.AccountModified{
          id: account.id,
          type: :expenses,
          notes: "no so global expenses account"
        }

      assert :ok == Conta.Projector.Ledger.handle(event, metadata)

      assert %Conta.Projector.Ledger.Account{
        name: ["Expenses"],
        ledger: "default",
        type: :expenses,
        notes: "no so global expenses account"
      } = Repo.get!(Conta.Projector.Ledger.Account, account.id)
    end

    test "rename account", metadata do
      balance1 = build(:balance, %{amount: 100_0})
      balance2 = build(:balance, %{amount: 90_0})
      balance3 = build(:balance, %{amount: 10_0})

      account1 = insert(:account, %{name: ~w[Assets], balances: [balance1]})
      account2 = insert(:account, %{name: ~w[Assets Bank], parent_id: account1.id, balances: [balance2]})
      account3 = insert(:account, %{name: ~w[Assets Account], parent_id: account1.id, balances: [balance3]})

      event =
        %Conta.Event.AccountRenamed{
          id: account3.id,
          prev_name: ["Assets", "Account"],
          new_name: ["Assets", "Bank", "Account"]
        }

      assert :ok == Conta.Projector.Ledger.handle(event, metadata)

      assert %Conta.Projector.Ledger.Account{
        name: ~w[Assets],
        ledger: "default",
        type: :assets,
        subaccounts: [
          %Conta.Projector.Ledger.Account{
            name: ~w[Assets Bank],
            ledger: "default",
            type: :assets,
            subaccounts: [
              %Conta.Projector.Ledger.Account{
                name: ~w[Assets Bank Account],
                ledger: "default",
                type: :assets
              }
            ]
          }
        ]
      } =
        Repo.get!(Conta.Projector.Ledger.Account, account1.id)
        |> Repo.preload([:balances, subaccounts: [:balances, subaccounts: :balances]])
    end
  end
end
