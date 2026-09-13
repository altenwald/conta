defmodule ContaWeb.EntryLiveTest do
  use ContaWeb.ConnCase

  import Commanded.Assertions.EventAssertions
  import Conta.Commanded.Application, only: [dispatch: 1]
  import Conta.LedgerFixtures
  import Phoenix.LiveViewTest

  alias Conta.AccountsFixtures
  alias Conta.Command.SetAccount

  setup do
    user = AccountsFixtures.insert(:user) |> AccountsFixtures.confirm_user()

    assets = insert(:account, %{name: ~w[Assets]})
    bank = insert(:account, %{name: ~w[Assets Bank]})
    expenses = insert(:account, %{name: ~w[Expenses], type: :expenses})
    supermarket = insert(:account, %{name: ~w[Expenses Supermarket], type: :expenses})

    dispatch(%SetAccount{id: assets.id, name: ~w[Assets], type: :assets, currency: :EUR, ledger: "default"})

    dispatch(%SetAccount{
      id: bank.id,
      name: ~w[Assets Bank],
      type: :assets,
      currency: :EUR,
      ledger: "default"
    })

    dispatch(%SetAccount{
      id: expenses.id,
      name: ~w[Expenses],
      type: :expenses,
      currency: :EUR,
      ledger: "default"
    })

    dispatch(%SetAccount{
      id: supermarket.id,
      name: ~w[Expenses Supermarket],
      type: :expenses,
      currency: :EUR,
      ledger: "default"
    })

    wait_for_event(Conta.Commanded.Application, Conta.Event.AccountCreated, fn event ->
      event.name == ~w[Expenses Supermarket]
    end)

    entry =
      insert(:entry, %{
        account_name: ~w[Assets Bank],
        related_account_name: ~w[Expenses Supermarket],
        credit: 10_00,
        debit: 0
      })

    insert(:entry, %{
      transaction_id: entry.transaction_id,
      account_name: ~w[Expenses Supermarket],
      related_account_name: ~w[Assets Bank],
      credit: 0,
      debit: 10_00,
      change_credit: 0,
      change_debit: 10_00
    })

    %{
      user: user,
      assets: assets,
      bank: bank,
      expenses: expenses,
      supermarket: supermarket,
      entry: entry
    }
  end

  describe "Index" do
    test "lists all ledger_entries", %{conn: conn} = data do
      conn = log_in_user(conn, data.user)
      {:ok, _index_live, html} = live(conn, ~p"/ledger/accounts/#{data.bank}/entries")

      assert html =~ "Listing Ledger entries"
      assert html =~ "Buy something"
      assert html =~ ">Assets<"
      assert html =~ ">Bank<"
      assert html =~ "Expenses.Supermarket"
      assert html =~ "10,00 €"
    end

    test "keeps the active search filter when the view is reset", %{conn: conn} = data do
      insert(:entry, %{
        description: "Pay rent",
        on_date: ~D[2024-01-02],
        account_name: ~w[Assets Bank],
        related_account_name: ~w[Expenses Supermarket]
      })

      conn = log_in_user(conn, data.user)
      {:ok, index_live, _html} = live(conn, ~p"/ledger/accounts/#{data.bank}/entries")

      html =
        index_live
        |> element("form[role=search]")
        |> render_change(%{"search" => "rent"})

      assert html =~ "Pay rent"
      refute html =~ "Buy something"

      # same refresh path triggered after creating, duplicating or deleting an entry
      send(index_live.pid, {:reset_view, "transaction-id"})
      html = render(index_live)

      assert html =~ "Pay rent"
      refute html =~ "Buy something"
    end

    test "renders AccountSelectComponent in new entry modal and creates transaction", %{
      conn: conn,
      bank: bank,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, index_live, _html} = live(conn, ~p"/ledger/accounts/#{bank}/entries")

      assert index_live
             |> element("a", "New Entry")
             |> render_click() =~ "New Entry"

      assert_patch(index_live, ~p"/ledger/accounts/#{bank}/entries/new")

      # Both account selectors are rendered
      assert has_element?(index_live, "#account-transaction-account-name")
      assert has_element?(index_live, "#account-transaction-related-account-name")

      # Main account is pre-filled with current account name
      assert has_element?(
               index_live,
               "#account-transaction-account-name input[value=\"Assets.Bank\"]"
             )

      # Related account search and selection via AccountSelectComponent
      index_live
      |> element("#account-transaction-related-account-name-input")
      |> render_keyup(%{"query" => "super"})

      assert has_element?(
               index_live,
               "#account-transaction-related-account-name button[role=option]",
               "Expenses.Supermarket"
             )

      index_live
      |> element(
        "#account-transaction-related-account-name button[role=option]",
        "Expenses.Supermarket"
      )
      |> render_click()

      # Dropdown closes upon selection
      refute has_element?(index_live, "#account-transaction-related-account-name [role=listbox]")

      # Submit the transaction
      index_live
      |> form("#account-transaction-form", %{
        "account_transaction" => %{
          "account_name" => "Assets.Bank",
          "related_account_name" => "Expenses.Supermarket",
          "description" => "Weekly grocery shopping",
          "amount" => "45.50"
        }
      })
      |> render_submit()

      assert_patch(index_live, ~p"/ledger/accounts/#{bank}/entries")
      assert render(index_live) =~ "Account transaction created successfully"
    end

    test "updates entry in listing using AccountSelectComponent", %{
      conn: conn,
      bank: bank,
      entry: entry,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, index_live, _html} = live(conn, ~p"/ledger/accounts/#{bank}/entries")

      assert index_live
             |> element("#ledger_entries-#{entry.id} a[title='Edit']")
             |> render_click() =~ "Edit Entry"

      assert_patch(index_live, ~p"/ledger/accounts/#{bank}/entries/#{entry.transaction_id}/edit")

      assert has_element?(index_live, "#account-transaction-account-name")
      assert has_element?(index_live, "#account-transaction-related-account-name")

      # Search and change related account
      index_live
      |> element("#account-transaction-related-account-name-input")
      |> render_keyup(%{"query" => "Expenses"})

      assert has_element?(
               index_live,
               "#account-transaction-related-account-name button[role=option]",
               "Expenses"
             )

      index_live
      |> element("#account-transaction-related-account-name button[phx-value-account='Expenses']")
      |> render_click()

      refute has_element?(index_live, "#account-transaction-related-account-name [role=listbox]")

      index_live
      |> form("#account-transaction-form", %{
        "account_transaction" => %{
          "account_name" => "Assets.Bank",
          "related_account_name" => "Expenses",
          "description" => "Updated description",
          "amount" => "15.00"
        }
      })
      |> render_submit()

      assert_patch(index_live, ~p"/ledger/accounts/#{bank}/entries")
      assert render(index_live) =~ "Account transaction updated successfully"
    end

    test "supports breakdown entries with AccountSelectComponent", %{
      conn: conn,
      bank: bank,
      user: user
    } do
      conn = log_in_user(conn, user)
      {:ok, index_live, _html} = live(conn, ~p"/ledger/accounts/#{bank}/entries/new")

      # Toggle breakdown
      index_live
      |> element("#account-transaction-form")
      |> render_change(%{
        "account_transaction" => %{
          "breakdown" => "true"
        }
      })

      assert has_element?(index_live, "a", "Add Entry")

      # Add an entry to breakdown
      index_live
      |> element("a", "Add Entry")
      |> render_click()

      # AccountSelectComponent rendered for the breakdown entry
      assert has_element?(index_live, "#account-transaction-entry-0-account-name")

      # Select account in breakdown entry
      index_live
      |> element("#account-transaction-entry-0-account-name-input")
      |> render_keyup(%{"query" => "super"})

      assert has_element?(
               index_live,
               "#account-transaction-entry-0-account-name button[role=option]",
               "Expenses.Supermarket"
             )

      index_live
      |> element("#account-transaction-entry-0-account-name button[phx-value-account='Expenses.Supermarket']")
      |> render_click()

      refute has_element?(index_live, "#account-transaction-entry-0-account-name [role=listbox]")
    end

    test "deletes entry in listing", %{conn: conn, entry: entry, bank: bank, user: user} do
      conn = log_in_user(conn, user)
      {:ok, index_live, _html} = live(conn, ~p"/ledger/accounts/#{bank}/entries")

      assert index_live
             |> element("#ledger_entries-#{entry.id} a[title='Delete']")
             |> render_click()

      wait_for_event(Conta.Commanded.Application, Conta.Event.TransactionRemoved)
      send(index_live.pid, {:reset_view, entry.transaction_id})

      refute has_element?(index_live, "#ledger_entries-#{entry.id}")
    end
  end
end
