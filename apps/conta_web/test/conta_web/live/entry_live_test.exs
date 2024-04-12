defmodule ContaWeb.EntryLiveTest do
  use ContaWeb.ConnCase

  import Phoenix.LiveViewTest
  import Conta.Factory

  @create_attrs %{description: "Buy Ketchup", credit: 5_00}
  @update_attrs %{}
  @invalid_attrs %{}

  setup do
    assets = insert(:account, %{name: ~w[Assets]})
    bank = insert(:account, %{name: ~w[Assets Bank]})
    expenses = insert(:account, %{name: ~w[Expenses], type: :expenses})
    supermarket = insert(:account, %{name: ~w[Expenses Supermarket], type: :expenses})
    entry = insert(:entry, %{account_name: ~w[Assets Bank], related_account_name: ~w[Expenses Supermarket]})
    %{
      assets: assets,
      bank: bank,
      expenses: expenses,
      supermarket: supermarket,
      entry: entry
    }
  end

  describe "Index" do
    test "lists all ledger_entries", %{conn: conn} = data do
      {:ok, _index_live, html} = live(conn, ~p"/ledger/accounts/#{data.bank}/entries")

      assert html =~ "Listing Ledger entries"
      assert html =~ "Buy something"
      assert html =~ "Assets.Bank"
      assert html =~ "Expenses.Supermarket"
      assert html =~ "10,00 €"
    end

    test "saves new entry", %{conn: conn} = data do
      {:ok, index_live, _html} = live(conn, ~p"/ledger/accounts/#{data.bank}/entries")

      assert index_live
             |> element("a", "New Entry")
             |> render_click() =~ "New Entry"
             |> open_browser()

      assert_patch(index_live, ~p"/ledger/accounts/#{data.bank}/entries/new")

      assert index_live
             |> form("#entry-form", entry: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#entry-form", entry: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/ledger/accounts/#{data.bank}/entries")

      html = render(index_live)
      assert html =~ "Entry created successfully"
    end

    test "updates entry in listing", %{conn: conn, entry: entry} = data do
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

    test "deletes entry in listing", %{conn: conn, entry: entry} = data do
      {:ok, index_live, _html} = live(conn, ~p"/ledger/accounts/#{data.bank.id}/entries")

      assert index_live
             |> element("#ledger_entries-#{entry.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#ledger_entries-#{entry.id}")
    end
  end

  describe "Show" do
    test "displays entry", %{conn: conn, entry: entry} do
      {:ok, _show_live, html} = live(conn, ~p"/ledger_entries/#{entry}")

      assert html =~ "Show Entry"
    end

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
