defmodule Conta.Projector.LedgerTest do
  use Conta.DataCase
  import Conta.LedgerFixtures
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

      assert :ok == Ledger.handle(event, metadata)

      assert %Ledger.Account{
        id: "b6ad9e02-0e37-404c-953a-daa8c3d23880",
        name: ["Assets"],
        ledger: "default",
        type: :assets,
        notes: "hello there!"
      } = Repo.get!(Ledger.Account, "b6ad9e02-0e37-404c-953a-daa8c3d23880")
    end

    test "update account", metadata do
      account = insert(:account, %{name: ["Expenses"], type: :expenses, notes: "global expenses account"})

      event =
        %Conta.Event.AccountModified{
          id: account.id,
          type: :expenses,
          notes: "no so global expenses account"
        }

      assert :ok == Ledger.handle(event, metadata)

      assert %Ledger.Account{
        name: ["Expenses"],
        ledger: "default",
        type: :expenses,
        notes: "no so global expenses account"
      } = Repo.get!(Conta.Projector.Ledger.Account, account.id)
    end

    test "rename account", metadata do
      balance1 = build(:balance, %{amount: 100_00})
      balance2 = build(:balance, %{amount: 90_00})
      balance3 = build(:balance, %{amount: 10_00})

      account1 = insert(:account, %{name: ~w[Assets], balances: [balance1]})
      _account2 = insert(:account, %{name: ~w[Assets Bank], parent_id: account1.id, balances: [balance2]})
      account3 = insert(:account, %{name: ~w[Assets Account], parent_id: account1.id, balances: [balance3]})

      event =
        %Conta.Event.AccountRenamed{
          id: account3.id,
          prev_name: ["Assets", "Account"],
          new_name: ["Assets", "Bank", "Account"]
        }

      assert :ok == Ledger.handle(event, metadata)

      assert %Ledger.Account{
        name: ~w[Assets],
        ledger: "default",
        type: :assets,
        balances: [%Ledger.Balance{amount: %Money{amount: 100_00}}],
        subaccounts: [
          %Ledger.Account{
            name: ~w[Assets Bank],
            ledger: "default",
            balances: [%Ledger.Balance{amount: %Money{amount: 100_00}}],
            type: :assets,
            subaccounts: [
              %Ledger.Account{
                name: ~w[Assets Bank Account],
                ledger: "default",
                balances: [%Ledger.Balance{amount: %Money{amount: 10_00}}],
                type: :assets
              }
            ]
          }
        ]
      } =
        Repo.get!(Ledger.Account, account1.id)
        |> Repo.preload([:balances, subaccounts: [:balances, subaccounts: :balances]])
    end
  end

  describe "transactions" do
    test "create successfully", metadata do
      balance1 = build(:balance, %{amount: 100_00})
      balance2 = build(:balance, %{amount: 90_00})
      balance3 = build(:balance, %{amount: 90_00})
      balance4 = build(:balance, %{amount: 50_00})
      balance5 = build(:balance, %{amount: 50_00})

      account1 = insert(:account, %{name: ~w[Assets], balances: [balance1]})
      account2 = insert(:account, %{name: ~w[Assets Bank], parent_id: account1.id, balances: [balance2]})
      account3 = insert(:account, %{name: ~w[Assets Bank Account], parent_id: account2.id, balances: [balance3]})
      account4 = insert(:account, %{name: ~w[Expenses], type: :expenses, balances: [balance4]})
      account5 = insert(:account, %{name: ~w[Expenses Groceries], type: :expenses, parent_id: account4.id, balances: [balance5]})

      insert(:entry, %{on_date: ~D[2024-05-31], account_name: account3.name, debit: 90_00, balance: 90_00, description: "initial"})
      insert(:entry, %{on_date: ~D[2024-05-31], account_name: account5.name, debit: 50_00, balance: 50_00, description: "initial"})

      event = %Conta.Event.TransactionCreated{
        id: "814d6052-8594-4964-8485-778762d8c701",
        ledger: "default",
        on_date: ~D[2024-06-01],
        entries: [
          %Conta.Event.TransactionCreated.Entry{
            description: "Dinner",
            account_name: ~w[Assets Bank Account],
            credit: 12_50,
            debit: 0,
            balance: 77_50
          },
          %Conta.Event.TransactionCreated.Entry{
            description: "Dinner",
            account_name: ~w[Expenses Groceries],
            credit: 0,
            debit: 12_50,
            balance: 62_50
          }
        ]
      }

      assert :ok == Ledger.handle(event, metadata)

      [
        %Ledger.Entry{
          on_date: ~D[2024-06-01],
          description: "Dinner",
          credit: %Money{amount: 12_50, currency: :EUR},
          debit: %Money{amount: 0, currency: :EUR},
          balance: %Money{amount: 77_50, currency: :EUR},
          transaction_id: "814d6052-8594-4964-8485-778762d8c701",
          account_name: ["Assets", "Bank", "Account"],
          breakdown: false,
          related_account_name: ["Expenses", "Groceries"]
        },
        %Ledger.Entry{
          on_date: ~D[2024-06-01],
          description: "Dinner",
          credit: %Money{amount: 0, currency: :EUR},
          debit: %Money{amount: 12_50, currency: :EUR},
          balance: %Money{amount: 6250, currency: :EUR},
          transaction_id: "814d6052-8594-4964-8485-778762d8c701",
          account_name: ["Expenses", "Groceries"],
          breakdown: false,
          related_account_name: ["Assets", "Bank", "Account"]
        }
      ] = Repo.all(Ledger.Entry) |> Enum.reject(& &1.description == "initial")

      assert %Ledger.Account{
        name: ~w[Assets],
        balances: [
          %Ledger.Balance{
            currency: :EUR,
            amount: %Money{amount: 87_50}
          }
        ]
      } = Repo.get!(Ledger.Account, account1.id) |> Repo.preload(:balances)

      assert %Ledger.Account{
        name: ~w[Assets Bank],
        balances: [
          %Ledger.Balance{
            currency: :EUR,
            amount: %Money{amount: 77_50}
          }
        ]
      } = Repo.get!(Ledger.Account, account2.id) |> Repo.preload(:balances)

      assert %Ledger.Account{
        name: ~w[Assets Bank Account],
        balances: [
          %Ledger.Balance{
            currency: :EUR,
            amount: %Money{amount: 77_50}
          }
        ]
      } = Repo.get!(Ledger.Account, account3.id) |> Repo.preload(:balances)

      assert %Ledger.Account{
        name: ~w[Expenses],
        balances: [
          %Ledger.Balance{
            currency: :EUR,
            amount: %Money{amount: 62_50}
          }
        ]
      } = Repo.get!(Ledger.Account, account4.id) |> Repo.preload(:balances)

      assert %Ledger.Account{
        name: ~w[Expenses Groceries],
        balances: [
          %Ledger.Balance{
            currency: :EUR,
            amount: %Money{amount: 62_50}
          }
        ]
      } = Repo.get!(Ledger.Account, account5.id) |> Repo.preload(:balances)
    end

    test "remove successfully", metadata do
      balance1 = build(:balance, %{amount: 100_00})
      balance2 = build(:balance, %{amount: 90_00})
      balance3 = build(:balance, %{amount: 90_00})
      balance4 = build(:balance, %{amount: 50_00})
      balance5 = build(:balance, %{amount: 50_00})

      account1 = insert(:account, %{name: ~w[Assets], balances: [balance1]})
      account2 = insert(:account, %{name: ~w[Assets Bank], parent_id: account1.id, balances: [balance2]})
      account3 = insert(:account, %{name: ~w[Assets Bank Account], parent_id: account2.id, balances: [balance3]})
      account4 = insert(:account, %{name: ~w[Expenses], type: :expenses, balances: [balance4]})
      account5 = insert(:account, %{name: ~w[Expenses Supermarket], type: :expenses, parent_id: account4.id, balances: [balance5]})

      # Assets.Bank.Account (90_00)
      # -------------------
      # Initial                   ---                    150_00    0_00   150_00
      # Energy bill               Expenses.Supplies        0_00   30_00   120_00
      # Buy something             Expenses.Supermarket     0_00   10_00   110_00
      # Carity                    Expenses.Other           0_00   20_00    90_00

      initial = %Conta.Projector.Ledger.Entry{} = insert(:entry, %{
        on_date: ~D[2024-05-31],
        transaction_id: "f3093f1f-0a55-4356-b925-831035a8bca5",
        account_name: account3.name,
        description: "initial",
        debit: 150_00,
        balance: 150_00
      })

      no_changed_line = %Conta.Projector.Ledger.Entry{} = insert(:entry, %{
        on_date: ~D[2024-06-01],
        transaction_id: "f3093f1f-0a55-4356-b925-831035a8bca6",
        account_name: account3.name,
        related_account_name: ~w[Expenses Supplies],
        description: "Energy bill",
        credit: 30_00,
        balance: 120_00
      })

      leg_a_entry = %Conta.Projector.Ledger.Entry{} = insert(:entry, %{
        on_date: ~D[2024-06-01],
        transaction_id: "f3093f1f-0a55-4356-b925-831035a8bca7",
        account_name: account3.name,
        related_account_name: account5.name,
        credit: 10_00,
        balance: 110_00
      })
      _leg_b_entry = %Conta.Projector.Ledger.Entry{} = insert(:entry, %{
        on_date: ~D[2024-06-01],
        transaction_id: "f3093f1f-0a55-4356-b925-831035a8bca7",
        account_name: leg_a_entry.related_account_name,
        related_account_name: leg_a_entry.account_name,
        credit: leg_a_entry.debit,
        debit: leg_a_entry.credit
      })

      _changed_line = %Conta.Projector.Ledger.Entry{} = insert(:entry, %{
        on_date: ~D[2024-06-01],
        transaction_id: "f3093f1f-0a55-4356-b925-831035a8bca8",
        account_name: ~w[Assets Bank Account],
        related_account_name: ~w[Expenses Other],
        description: "Carity",
        credit: 20_00,
        balance: 90_00
      })

      event = %Conta.Event.TransactionRemoved{
        id: leg_a_entry.transaction_id,
        ledger: "default",
        entries: [
          %Conta.Event.TransactionRemoved.Entry{
            account_name: account5.name,
            credit: leg_a_entry.credit,
            debit: 10_00,
            balance: 40_00,
            currency: :EUR
          },
          %Conta.Event.TransactionRemoved.Entry{
            account_name: account3.name,
            credit: 10_00,
            debit: 0,
            balance: 100_00,
            currency: :EUR
          }
        ]
      }

      assert :ok == Ledger.handle(event, metadata)

      assert [^initial, ^no_changed_line, new_changed_line] =
        Repo.all(Ledger.Entry) |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)

      assert %Ledger.Entry{
        account_name: ~w[Assets Bank Account],
        balance: %Money{amount: 100_00},
        credit: %Money{amount: 20_00},
        debit: %Money{amount: 0},
        description: "Carity",
        related_account_name: ~w[Expenses Other]
      } = new_changed_line

      assert %Ledger.Account{
        name: ~w[Assets],
        balances: [
          %Ledger.Balance{
            currency: :EUR,
            amount: %Money{amount: 110_00}
          }
        ]
      } = Repo.get!(Ledger.Account, account1.id) |> Repo.preload(:balances)

      assert %Ledger.Account{
        name: ~w[Assets Bank],
        balances: [
          %Ledger.Balance{
            currency: :EUR,
            amount: %Money{amount: 100_00}
          }
        ]
      } = Repo.get!(Ledger.Account, account2.id) |> Repo.preload(:balances)

      assert %Ledger.Account{
        name: ~w[Assets Bank Account],
        balances: [
          %Ledger.Balance{
            currency: :EUR,
            amount: %Money{amount: 100_00}
          }
        ]
      } = Repo.get!(Ledger.Account, account3.id) |> Repo.preload(:balances)

      assert %Ledger.Account{
        name: ~w[Expenses],
        balances: [
          %Ledger.Balance{
            currency: :EUR,
            amount: %Money{amount: 40_00}
          }
        ]
      } = Repo.get!(Ledger.Account, account4.id) |> Repo.preload(:balances)

      assert %Ledger.Account{
        name: ~w[Expenses Supermarket],
        balances: [
          %Ledger.Balance{
            currency: :EUR,
            amount: %Money{amount: 40_00}
          }
        ]
      } = Repo.get!(Ledger.Account, account5.id) |> Repo.preload(:balances)
    end
  end
end
