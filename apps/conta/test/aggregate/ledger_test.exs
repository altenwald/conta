defmodule Conta.Aggregate.LedgerTest do
  use ExUnit.Case
  alias Conta.Aggregate.Ledger
  alias Conta.Command.RemoveAccountTransaction
  alias Conta.Command.SetAccount
  alias Conta.Command.SetAccountTransaction
  alias Conta.Event.AccountCreated
  alias Conta.Event.AccountModified
  alias Conta.Event.AccountRenamed
  alias Conta.Event.TransactionCreated
  alias Conta.Event.TransactionRemoved

  describe "ledger create account execute" do
    test "create account successfully" do
      command =
        %SetAccount{
          name: ["Assets"],
          type: :assets,
          currency: :EUR,
          notes: nil,
          ledger: "default"
        }

      ledger = %Ledger{name: "default"}
      event = Ledger.execute(ledger, command)

      assert %AccountCreated{
        id: account_id,
        name: ["Assets"],
        type: :assets,
        currency: :EUR,
        notes: nil,
        ledger: "default"
      } = event

      refute is_nil(account_id)

      ledger = Ledger.apply(ledger, event)

      assert %Ledger{
        name: "default",
        account_names: %{["Assets"] => ^account_id},
        accounts: %{
          ^account_id => %Ledger.Account{
            name: ["Assets"],
            type: :assets,
            currency: :EUR,
            notes: nil,
            balances: %{}
          }
        }
      } = ledger
    end

    test "modify account data successfully" do
      command =
        %SetAccount{
          # because we don't provide id, the aggregate search for it,
          # this way we don't need to know the ID unless we want to change
          # the name of the account.
          name: ["Assets"],
          type: :expenses,
          currency: :EUR,
          notes: "these are our assets",
          ledger: "default"
        }

      ledger = %Ledger{
        name: "default",
        account_names: %{["Assets"] => "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc"},
        accounts: %{
          "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc" => %Ledger.Account{
            id: "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc",
            name: ["Assets"],
            type: :assets,
            currency: "EUR",
            notes: nil,
            balances: %{}
          }
        }
      }

      assert [event] = Ledger.execute(ledger, command)

      assert %AccountModified{
        id: "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc",
        type: :expenses,
        currency: :EUR,
        notes: "these are our assets"
      } = event

      ledger = Ledger.apply(ledger, event)

      assert %Ledger{
        name: "default",
        account_names: %{["Assets"] => "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc"},
        accounts: %{
          "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc" => %Ledger.Account{
            id: "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc",
            name: ["Assets"],
            type: :expenses,
            currency: :EUR,
            notes: "these are our assets",
            balances: %{}
          }
        }
      } = ledger
    end

    test "cannot find parent modifying account" do
      command =
        %SetAccount{
          id: "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc",
          name: ["Assets", "Bank", "Account"],
          type: :expenses,
          currency: :EUR,
          notes: "these are our assets",
          ledger: "default"
        }

      ledger = %Ledger{
        name: "default",
        account_names: %{["Assets"] => "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc"},
        accounts: %{
          "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc" => %Ledger.Account{
            id: "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc",
            name: ["Assets"],
            type: :assets,
            currency: "EUR",
            notes: nil,
            balances: %{}
          }
        }
      }

      assert {:error, :invalid_parent_account} = Ledger.execute(ledger, command)
    end

    test "incorrect id changed into new account and existing name change into modify account" do
      command =
        %SetAccount{
          id: "00000000-0000-0000-0000-000000000000",
          name: ["Assets"],
          type: :expenses,
          currency: :EUR,
          notes: "these are our assets",
          ledger: "default"
        }

      ledger = %Ledger{
        name: "default",
        account_names: %{["Assets"] => "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc"},
        accounts: %{
          "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc" => %Ledger.Account{
            id: "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc",
            name: ["Assets"],
            type: :assets,
            currency: "EUR",
            notes: nil,
            balances: %{}
          }
        }
      }

      assert [event] = Ledger.execute(ledger, command)

      assert %AccountModified{
        id: "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc",
        type: :expenses,
        currency: :EUR,
        notes: "these are our assets"
      } == event
    end

    test "no changes modifying account" do
      command =
        %SetAccount{
          name: ["Assets"],
          type: :assets,
          currency: :EUR,
          ledger: "default"
        }

      ledger = %Ledger{
        name: "default",
        account_names: %{["Assets"] => "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc"},
        accounts: %{
          "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc" => %Ledger.Account{
            id: "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc",
            name: ["Assets"],
            type: :assets,
            currency: "EUR",
            notes: nil,
            balances: %{}
          }
        }
      }

      assert {:error, :no_changes} = Ledger.execute(ledger, command)
    end

    test "rename account successfully" do
      command =
        %SetAccount{
          id: "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc",
          name: ["Assets", "MyBank", "MyAccount"],
          type: :assets,
          currency: :EUR,
          ledger: "default"
        }

      ledger = %Ledger{
        name: "default",
        account_names: %{
          ["Assets"] => "e4d7e008-356e-45a0-83d3-9b25a235550a",
          ["Assets", "MyAcc"] => "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc",
          ["Assets", "MyBank"] => "82f8cbf4-a1f2-4c3b-9d7e-6898a5841829"
        },
        accounts: %{
          "e4d7e008-356e-45a0-83d3-9b25a235550a" => %Ledger.Account{
            id: "e4d7e008-356e-45a0-83d3-9b25a235550a",
            name: ["Assets"],
            type: :assets,
            currency: :EUR,
            notes: nil,
            balances: %{"EUR" => 100}
          },
          "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc" => %Ledger.Account{
            id: "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc",
            name: ["Assets", "MyAcc"],
            type: :assets,
            currency: :EUR,
            notes: nil,
            balances: %{"EUR" => 90}
          },
          "82f8cbf4-a1f2-4c3b-9d7e-6898a5841829" => %Ledger.Account{
            id: "82f8cbf4-a1f2-4c3b-9d7e-6898a5841829",
            name: ["Assets", "MyBank"],
            type: :assets,
            currency: :EUR,
            notes: nil,
            balances: %{"EUR" => 10}
          }
        }
      }

      assert [event] = Enum.sort(Ledger.execute(ledger, command))

      assert %AccountRenamed{
        id: "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc",
        prev_name: ["Assets", "MyAcc"],
        new_name: ["Assets", "MyBank", "MyAccount"],
        ledger: "default"
      } = event

      ledger = Ledger.apply(ledger, event)

      assert %Ledger{
        name: "default",
        account_names: %{
          ["Assets"] => "e4d7e008-356e-45a0-83d3-9b25a235550a",
          ["Assets", "MyBank"] => "82f8cbf4-a1f2-4c3b-9d7e-6898a5841829",
          ["Assets", "MyBank", "MyAccount"] => "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc"
        },
        accounts: %{
          "e4d7e008-356e-45a0-83d3-9b25a235550a" => %Ledger.Account{
            id: "e4d7e008-356e-45a0-83d3-9b25a235550a",
            name: ["Assets"],
            type: :assets,
            currency: :EUR,
            notes: nil,
            balances: %{"EUR" => 100}
          },
          "82f8cbf4-a1f2-4c3b-9d7e-6898a5841829" => %Ledger.Account{
            id: "82f8cbf4-a1f2-4c3b-9d7e-6898a5841829",
            name: ["Assets", "MyBank"],
            type: :assets,
            currency: :EUR,
            notes: nil,
            balances: %{"EUR" => 100}
          },
          "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc" => %Ledger.Account{
            id: "83dfbfb4-c7f0-4403-b656-b8ed4228f7bc",
            name: ["Assets", "MyBank", "MyAccount"],
            type: :assets,
            currency: :EUR,
            notes: nil,
            balances: %{"EUR" => 90}
          }
        }
      } = ledger
    end

    test "missing ledger fail for set account" do
      assert {:error, :missing_ledger} = Ledger.execute(nil, %SetAccount{currency: :EUR, ledger: nil})
    end

    test "invalid currency for set account" do
      assert {:error, :invalid_currency} = Ledger.execute(nil, %SetAccount{currency: :no_currency})
    end

    test "create account failure" do
      command =
        %SetAccount{
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

  describe "ledger create transaction" do
    test "basic successfully" do
      command =
        %SetAccountTransaction{
          ledger: "default",
          on_date: ~D[2024-01-31],
          entries: [
            %SetAccountTransaction.Entry{
              description: "Albert Heijn",
              account_name: ["Assets", "Cash"],
              credit: 5_00,
              debit: 0
            },
            %SetAccountTransaction.Entry{
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
          account_names: %{
            ["Assets"] => "bd625868-3bd3-4f2c-9cab-8d8b73018ed1",
            ["Assets", "Cash"] => "ab0c9ece-4aa5-48d5-ae08-7e89bd104fde",
            ["Assets", "PayPal"] => "569eb02b-da2c-42c8-ad89-c7ba1618c451",
            ["Expenses"] => "7c708316-43ed-4130-9c66-a1e063d10374",
            ["Expenses", "Supermarket"] => "4151bcd1-de24-48fc-a8de-e18d2aae0eb7"
          },
          accounts: %{
            "bd625868-3bd3-4f2c-9cab-8d8b73018ed1" => %Ledger.Account{
              name: ["Assets"],
              type: :assets,
              currency: :EUR,
              balances: %{EUR: 100_00, USD: 100_00}
            },
            "ab0c9ece-4aa5-48d5-ae08-7e89bd104fde" => %Ledger.Account{
              name: ["Assets", "Cash"],
              type: :assets,
              currency: :EUR,
              balances: %{EUR: 100_00}
            },
            "569eb02b-da2c-42c8-ad89-c7ba1618c451" => %Ledger.Account{
              name: ["Assets", "PayPal"],
              type: :assets,
              currency: :USD,
              balances: %{USD: 100_00}
            },
            "7c708316-43ed-4130-9c66-a1e063d10374" => %Ledger.Account{
              name: ["Expenses"],
              type: :expenses,
              currency: :EUR,
              balances: %{EUR: 50_00}
            },
            "4151bcd1-de24-48fc-a8de-e18d2aae0eb7" => %Ledger.Account{
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
            balance: %Money{amount: 95_00},
            credit: %Money{amount: 5_00}
          },
          %TransactionCreated.Entry{
            account_name: ["Expenses", "Supermarket"],
            description: "Albert Heijn",
            balance: %Money{amount: 55_00},
            debit: %Money{amount: 5_00}
          }
        ]
      } = event

      ledger = Ledger.apply(ledger, event)

      assert %Ledger{
        name: "default",
        account_names: %{
          ["Assets"] => "bd625868-3bd3-4f2c-9cab-8d8b73018ed1",
          ["Assets", "Cash"] => "ab0c9ece-4aa5-48d5-ae08-7e89bd104fde",
          ["Assets", "PayPal"] => "569eb02b-da2c-42c8-ad89-c7ba1618c451",
          ["Expenses"] => "7c708316-43ed-4130-9c66-a1e063d10374",
          ["Expenses", "Supermarket"] => "4151bcd1-de24-48fc-a8de-e18d2aae0eb7"
        },
        accounts: %{
          "bd625868-3bd3-4f2c-9cab-8d8b73018ed1" => %Ledger.Account{
            name: ["Assets"],
            type: :assets,
            currency: :EUR,
            balances: %{EUR: 95_00, USD: 100_00}
          },
          "ab0c9ece-4aa5-48d5-ae08-7e89bd104fde" => %Ledger.Account{
            name: ["Assets", "Cash"],
            type: :assets,
            currency: :EUR,
            balances: %{EUR: 95_00}
          },
          "569eb02b-da2c-42c8-ad89-c7ba1618c451" => %Ledger.Account{
            name: ["Assets", "PayPal"],
            type: :assets,
            currency: :USD,
            balances: %{USD: 100_00}
          },
          "7c708316-43ed-4130-9c66-a1e063d10374" => %Ledger.Account{
            name: ["Expenses"],
            type: :expenses,
            currency: :EUR,
            balances: %{EUR: 55_00}
          },
          "4151bcd1-de24-48fc-a8de-e18d2aae0eb7" => %Ledger.Account{
            name: ["Expenses", "Supermarket"],
            type: :expenses,
            currency: :EUR,
            balances: %{EUR: 55_00}
          }
        }
      } == ledger
    end

    test "different currencies successfully" do
      command =
        %SetAccountTransaction{
          ledger: "default",
          on_date: ~D[2024-01-04],
          entries: [
            %SetAccountTransaction.Entry{
              description: "Walmart",
              account_name: ["Expenses", "Supermarket"],
              credit: 0,
              debit: 475,
              change_currency: :USD,
              change_credit: 0,
              change_debit: 500,
              change_price: 1
            },
            %SetAccountTransaction.Entry{
              description: "Walmart",
              account_name: ["Assets", "PayPal"],
              credit: 500,
              debit: 0,
              change_currency: :EUR,
              change_credit: 475,
              change_debit: 0,
              change_price: 1
            }
          ]
        }

      ledger =
        %Ledger{
          name: "default",
          account_names: %{
            ["Assets"] => "bd625868-3bd3-4f2c-9cab-8d8b73018ed1",
            ["Assets", "Cash"] => "ab0c9ece-4aa5-48d5-ae08-7e89bd104fde",
            ["Assets", "PayPal"] => "569eb02b-da2c-42c8-ad89-c7ba1618c451",
            ["Expenses"] => "7c708316-43ed-4130-9c66-a1e063d10374",
            ["Expenses", "Supermarket"] => "4151bcd1-de24-48fc-a8de-e18d2aae0eb7"
          },
          accounts: %{
            "bd625868-3bd3-4f2c-9cab-8d8b73018ed1" => %Ledger.Account{
              name: ["Assets"],
              type: :assets,
              currency: :EUR,
              balances: %{EUR: 100_00, USD: 100_00}
            },
            "ab0c9ece-4aa5-48d5-ae08-7e89bd104fde" => %Ledger.Account{
              name: ["Assets", "Cash"],
              type: :assets,
              currency: :EUR,
              balances: %{EUR: 100_00}
            },
            "569eb02b-da2c-42c8-ad89-c7ba1618c451" => %Ledger.Account{
              name: ["Assets", "PayPal"],
              type: :assets,
              currency: :USD,
              balances: %{USD: 100_00}
            },
            "7c708316-43ed-4130-9c66-a1e063d10374" => %Ledger.Account{
              name: ["Expenses"],
              type: :expenses,
              currency: :EUR,
              balances: %{EUR: 50_00}
            },
            "4151bcd1-de24-48fc-a8de-e18d2aae0eb7" => %Ledger.Account{
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
        on_date: ~D[2024-01-04],
        entries: [
          %TransactionCreated.Entry{
            account_name: ["Expenses", "Supermarket"],
            description: "Walmart",
            balance: %Money{amount: 54_75},
            debit: %Money{amount: 4_75}
          },
          %TransactionCreated.Entry{
            account_name: ["Assets", "PayPal"],
            description: "Walmart",
            balance: %Money{amount: 95_00},
            credit: %Money{amount: 5_00}
          }
        ]
      } = event

      ledger = Ledger.apply(ledger, event)

      assert %Ledger{
        name: "default",
        account_names: %{
          ["Assets"] => "bd625868-3bd3-4f2c-9cab-8d8b73018ed1",
          ["Assets", "Cash"] => "ab0c9ece-4aa5-48d5-ae08-7e89bd104fde",
          ["Assets", "PayPal"] => "569eb02b-da2c-42c8-ad89-c7ba1618c451",
          ["Expenses"] => "7c708316-43ed-4130-9c66-a1e063d10374",
          ["Expenses", "Supermarket"] => "4151bcd1-de24-48fc-a8de-e18d2aae0eb7"
        },
        accounts: %{
          "bd625868-3bd3-4f2c-9cab-8d8b73018ed1" => %Ledger.Account{
            name: ["Assets"],
            type: :assets,
            currency: :EUR,
            balances: %{EUR: 100_00, USD: 95_00}
          },
          "ab0c9ece-4aa5-48d5-ae08-7e89bd104fde" => %Ledger.Account{
            name: ["Assets", "Cash"],
            type: :assets,
            currency: :EUR,
            balances: %{EUR: 100_00}
          },
          "569eb02b-da2c-42c8-ad89-c7ba1618c451" => %Ledger.Account{
            name: ["Assets", "PayPal"],
            type: :assets,
            currency: :USD,
            balances: %{USD: 95_00}
          },
          "7c708316-43ed-4130-9c66-a1e063d10374" => %Ledger.Account{
            name: ["Expenses"],
            type: :expenses,
            currency: :EUR,
            balances: %{EUR: 54_75}
          },
          "4151bcd1-de24-48fc-a8de-e18d2aae0eb7" => %Ledger.Account{
            name: ["Expenses", "Supermarket"],
            type: :expenses,
            currency: :EUR,
            balances: %{EUR: 54_75}
          }
        }
      } == ledger
    end

    test "not enough entries" do
      assert {:error, :not_enough_entries} = Ledger.execute(nil, %SetAccountTransaction{entries: []})
    end
  end

  describe "ledger remove transaction" do
    test "basic successfully" do
      ledger =
        %Ledger{
          name: "default",
          account_names: %{
            ["Assets"] => "bd625868-3bd3-4f2c-9cab-8d8b73018ed1",
            ["Assets", "Cash"] => "ab0c9ece-4aa5-48d5-ae08-7e89bd104fde",
            ["Assets", "PayPal"] => "569eb02b-da2c-42c8-ad89-c7ba1618c451",
            ["Expenses"] => "7c708316-43ed-4130-9c66-a1e063d10374",
            ["Expenses", "Supermarket"] => "4151bcd1-de24-48fc-a8de-e18d2aae0eb7"
          },
          accounts: %{
            "bd625868-3bd3-4f2c-9cab-8d8b73018ed1" => %Ledger.Account{
              name: ["Assets"],
              type: :assets,
              currency: :EUR,
              balances: %{EUR: 100_00, USD: 100_00}
            },
            "ab0c9ece-4aa5-48d5-ae08-7e89bd104fde" => %Ledger.Account{
              name: ["Assets", "Cash"],
              type: :assets,
              currency: :EUR,
              balances: %{EUR: 100_00}
            },
            "569eb02b-da2c-42c8-ad89-c7ba1618c451" => %Ledger.Account{
              name: ["Assets", "PayPal"],
              type: :assets,
              currency: :USD,
              balances: %{USD: 100_00}
            },
            "7c708316-43ed-4130-9c66-a1e063d10374" => %Ledger.Account{
              name: ["Expenses"],
              type: :expenses,
              currency: :EUR,
              balances: %{EUR: 50_00}
            },
            "4151bcd1-de24-48fc-a8de-e18d2aae0eb7" => %Ledger.Account{
              name: ["Expenses", "Supermarket"],
              type: :expenses,
              currency: :EUR,
              balances: %{EUR: 50_00}
            }
          }
        }

      command = %RemoveAccountTransaction{
        transaction_id: "f4bd5f91-f62c-4f19-9479-2595b7403262",
        entries: [
          %RemoveAccountTransaction.Entry{
            account_name: ~w[Assets PayPal],
            credit: 11_00,
            change_currency: :EUR,
            change_credit: 10_00
          },
          %RemoveAccountTransaction.Entry{
            account_name: ~w[Expenses Supermarket],
            debit: 10_00,
            change_currency: :USD,
            change_debit: 11_00
          }
        ]
      }

      assert %TransactionRemoved{
        ledger: "default",
        entries: [
          %TransactionRemoved.Entry{
            account_name: ["Assets", "PayPal"],
            credit: %Money{amount: 11_00, currency: :USD},
            debit: %Money{amount: 0, currency: :USD},
            balance: %Money{amount: 111_00, currency: :USD},
            currency: :USD
          },
          %TransactionRemoved.Entry{
            account_name: ["Expenses", "Supermarket"],
            credit: %Money{amount: 0},
            debit: %Money{amount: 10_00},
            balance: %Money{amount: 40_00},
            currency: :EUR
          }
        ]
      } = event = Ledger.execute(ledger, command)

      assert %Ledger{
        name: "default",
        account_names: %{
          ["Assets"] => "bd625868-3bd3-4f2c-9cab-8d8b73018ed1",
          ["Assets", "Cash"] => "ab0c9ece-4aa5-48d5-ae08-7e89bd104fde",
          ["Assets", "PayPal"] => "569eb02b-da2c-42c8-ad89-c7ba1618c451",
          ["Expenses"] => "7c708316-43ed-4130-9c66-a1e063d10374",
          ["Expenses", "Supermarket"] => "4151bcd1-de24-48fc-a8de-e18d2aae0eb7"
        },
        accounts: %{
          "bd625868-3bd3-4f2c-9cab-8d8b73018ed1" => %Ledger.Account{
            name: ["Assets"],
            type: :assets,
            currency: :EUR,
            balances: %{EUR: 100_00, USD: 111_00}
          },
          "ab0c9ece-4aa5-48d5-ae08-7e89bd104fde" => %Ledger.Account{
            name: ["Assets", "Cash"],
            type: :assets,
            currency: :EUR,
            balances: %{EUR: 100_00}
          },
          "569eb02b-da2c-42c8-ad89-c7ba1618c451" => %Ledger.Account{
            name: ["Assets", "PayPal"],
            type: :assets,
            currency: :USD,
            balances: %{USD: 111_00}
          },
          "7c708316-43ed-4130-9c66-a1e063d10374" => %Ledger.Account{
            name: ["Expenses"],
            type: :expenses,
            currency: :EUR,
            balances: %{EUR: 40_00}
          },
          "4151bcd1-de24-48fc-a8de-e18d2aae0eb7" => %Ledger.Account{
            name: ["Expenses", "Supermarket"],
            type: :expenses,
            currency: :EUR,
            balances: %{EUR: 40_00}
          }
        }
      } = Ledger.apply(ledger, event)
    end

    test "not enough entries" do
      assert {:error, :not_enough_entries} = Ledger.execute(nil, %RemoveAccountTransaction{entries: []})
    end
  end
end
