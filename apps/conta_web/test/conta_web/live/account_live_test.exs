defmodule ContaWeb.AccountLiveTest do
  use ContaWeb.ConnCase

  import Phoenix.LiveViewTest
  import Conta.LedgerFixtures

  @create_attrs %{}
  @update_attrs %{}
  @invalid_attrs %{}

  defp create_account(_) do
    account = account_fixture()
    %{account: account}
  end

  describe "Index" do
    setup [:create_account]

    test "lists all ledger_accounts", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/ledger_accounts")

      assert html =~ "Listing Ledger accounts"
    end

    test "saves new account", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/ledger_accounts")

      assert index_live |> element("a", "New Account") |> render_click() =~
               "New Account"

      assert_patch(index_live, ~p"/ledger_accounts/new")

      assert index_live
             |> form("#account-form", account: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#account-form", account: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/ledger_accounts")

      html = render(index_live)
      assert html =~ "Account created successfully"
    end

    test "updates account in listing", %{conn: conn, account: account} do
      {:ok, index_live, _html} = live(conn, ~p"/ledger_accounts")

      assert index_live |> element("#ledger_accounts-#{account.id} a", "Edit") |> render_click() =~
               "Edit Account"

      assert_patch(index_live, ~p"/ledger_accounts/#{account}/edit")

      assert index_live
             |> form("#account-form", account: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#account-form", account: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/ledger_accounts")

      html = render(index_live)
      assert html =~ "Account updated successfully"
    end

    test "deletes account in listing", %{conn: conn, account: account} do
      {:ok, index_live, _html} = live(conn, ~p"/ledger_accounts")

      assert index_live |> element("#ledger_accounts-#{account.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#ledger_accounts-#{account.id}")
    end
  end

  describe "Show" do
    setup [:create_account]

    test "displays account", %{conn: conn, account: account} do
      {:ok, _show_live, html} = live(conn, ~p"/ledger_accounts/#{account}")

      assert html =~ "Show Account"
    end

    test "updates account within modal", %{conn: conn, account: account} do
      {:ok, show_live, _html} = live(conn, ~p"/ledger_accounts/#{account}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Account"

      assert_patch(show_live, ~p"/ledger_accounts/#{account}/show/edit")

      assert show_live
             |> form("#account-form", account: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#account-form", account: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/ledger_accounts/#{account}")

      html = render(show_live)
      assert html =~ "Account updated successfully"
    end
  end
end
