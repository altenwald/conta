defmodule ContaWeb.EntryLiveTest do
  use ContaWeb.ConnCase

  import Conta.LedgerFixtures
  import Phoenix.LiveViewTest

  alias Conta.AccountsFixtures

  @create_attrs %{description: "Buy Ketchup", credit: 5_00}
  @update_attrs %{}
  @invalid_attrs %{}

  setup do
    user = AccountsFixtures.insert(:user) |> AccountsFixtures.confirm_user()
    assets = insert(:account, %{name: ~w[Assets]})
    bank = insert(:account, %{name: ~w[Assets Bank]})
    expenses = insert(:account, %{name: ~w[Expenses], type: :expenses})
    supermarket = insert(:account, %{name: ~w[Expenses Supermarket], type: :expenses})

    entry =
      insert(:entry, %{
        account_name: ~w[Assets Bank],
        related_account_name: ~w[Expenses Supermarket]
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

    @tag skip: :broken
    test "saves new entry", %{conn: conn} = data do
      conn = log_in_user(conn, data.user)
      {:ok, index_live, _html} = live(conn, ~p"/ledger/accounts/#{data.bank}/entries")

      assert index_live
             |> element("a", "New Entry")
             |> render_click() =~ "New Entry"

      assert_patch(index_live, ~p"/ledger/accounts/#{data.bank}/entries/new")

      assert index_live
             |> form("#account-transaction-form", entry: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#account-transaction-form", entry: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/ledger/accounts/#{data.bank}/entries")

      html = render(index_live)
      assert html =~ "Entry created successfully"
    end

    @tag skip: :broken
    test "updates entry in listing", %{conn: conn, entry: entry} = data do
      conn = log_in_user(conn, data.user)
      {:ok, index_live, _html} = live(conn, ~p"/ledger/accounts/#{data.bank}/entries")

      assert index_live
             |> element("#ledger_entries-#{entry.id} a", "Edit")
             |> render_click() =~ "Edit Entry"

      assert_patch(index_live, ~p"/ledger/accounts/#{data.bank}/entries/#{entry}/edit")

      assert index_live
             |> form("#entry-form", entry: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#entry-form", entry: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/ledger/accounts/#{data.bank}/entries")

      html = render(index_live)
      assert html =~ "Entry updated successfully"
    end

    @tag skip: :broken
    test "deletes entry in listing", %{conn: conn, entry: entry} = data do
      conn = log_in_user(conn, data.user)
      {:ok, index_live, _html} = live(conn, ~p"/ledger/accounts/#{data.bank.id}/entries")

      assert index_live
             |> element("#ledger_entries-#{entry.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#ledger_entries-#{entry.id}")
    end
  end

  describe "Show" do
    @tag skip: :broken
    test "displays entry", %{conn: conn, entry: entry} do
      {:ok, _show_live, html} = live(conn, ~p"/ledger_entries/#{entry}")

      assert html =~ "Show Entry"
    end

    @tag skip: :broken
    test "updates entry within modal", %{conn: conn, entry: entry} do
      {:ok, show_live, _html} = live(conn, ~p"/ledger_entries/#{entry}")

      assert show_live
             |> element("a", "Edit")
             |> render_click() =~ "Edit Entry"

      assert_patch(show_live, ~p"/ledger_entries/#{entry}/show/edit")

      assert show_live
             |> form("#entry-form", entry: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#entry-form", entry: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/ledger_entries/#{entry}")

      html = render(show_live)
      assert html =~ "Entry updated successfully"
    end
  end
end
