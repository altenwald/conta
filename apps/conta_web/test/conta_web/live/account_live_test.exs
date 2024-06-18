defmodule ContaWeb.AccountLiveTest do
  use ContaWeb.ConnCase, async: false

  import Commanded.Assertions.EventAssertions
  import Conta.LedgerFixtures
  import Phoenix.LiveViewTest

  alias Conta.AccountsFixtures
  alias Conta.Repo

  @create_attrs %{ledger: "default", simple_name: "Assets", type: "assets", currency: "EUR"}
  @update_attrs %{
    ledger: "default",
    simple_name: "Assets",
    type: "assets",
    currency: "USD",
    notes: "Ok"
  }
  @invalid_attrs %{simple_name: "", type: ""}

  setup %{conn: conn} do
    Repo.delete_all("ledger_balances")
    Repo.delete_all("ledger_accounts")
    Repo.delete_all("stats_income")
    Repo.delete_all("stats_outcome")
    Repo.delete_all("stats_patrimony")
    Repo.delete_all("stats_profits_loses")
    Repo.delete_all("stats_accounts")
    Repo.delete_all("users_tokens")
    Repo.delete_all("users")

    user = AccountsFixtures.insert(:user) |> AccountsFixtures.confirm_user()

    conn = log_in_user(conn, user)
    %{conn: conn, user: user}
  end

  defp create_account do
    Phoenix.PubSub.subscribe(Conta.PubSub, "event:account_created:default")

    :ok = Conta.Ledger.set_account(["Expenses"], :expenses)
    wait_for_event(Conta.Commanded.Application, Conta.Event.AccountCreated)

    assert_receive %{id: account_id}, 1500
    Conta.Repo.get!(Conta.Projector.Ledger.Account, account_id)
  end

  describe "Index" do
    test "lists all ledger_accounts", %{conn: conn} do
      assets = insert(:account, %{name: ["Assets"]})
      bank = insert(:account, %{name: ["Assets", "Bank"]})

      {:ok, _index_live, html} = live(conn, ~p"/ledger/accounts")

      assert html =~ "Dashboard"
      assert html =~ "Accounts"
      assert html =~ ~p"/ledger/accounts/#{assets}/edit"
      assert html =~ ~p"/ledger/accounts/#{bank}/edit"
      assert html =~ ~p"/ledger/accounts/#{assets}/entries"
      assert html =~ ~p"/ledger/accounts/#{bank}/entries"
    end

    test "saves new account", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/ledger/accounts")

      assert index_live
             |> element("a", "New Account")
             |> render_click() =~ "New Account"

      assert_patch(index_live, ~p"/ledger/accounts/new")

      assert index_live
             |> form("#account-form", set_account: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#account-form", set_account: @create_attrs)
             |> render_submit()

      wait_for_event(Conta.Commanded.Application, Conta.Event.AccountCreated)

      assert_patch(index_live, ~p"/ledger/accounts")

      html = render(index_live)
      assert html =~ "Account created successfully"
    end

    test "updates account in listing", %{conn: conn} do
      account = create_account()
      {:ok, index_live, _html} = live(conn, ~p"/ledger/accounts")

      assert index_live
             |> element("#ledger_accounts-#{account.id} a[title='Edit']")
             |> render_click() =~ "Edit Account"

      assert_patch(index_live, ~p"/ledger/accounts/#{account}/edit")

      assert index_live
             |> form("#account-form", set_account: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#account-form", set_account: @update_attrs)
             |> render_submit()

      wait_for_event(Conta.Commanded.Application, Conta.Event.AccountModified)

      assert_patch(index_live, ~p"/ledger/accounts")

      html = render(index_live)
      assert html =~ "Account updated successfully"
    end

    test "deletes account in listing", %{conn: conn} do
      account = create_account()
      {:ok, index_live, _html} = live(conn, ~p"/ledger/accounts")

      assert index_live
             |> element("#ledger_accounts-#{account.id} a[title='Delete']")
             |> render_click()

      wait_for_event(Conta.Commanded.Application, Conta.Event.AccountRemoved)

      refute has_element?(index_live, "#ledger_accounts-#{account.id}")
    end
  end

  describe "Show" do
    test "displays account", %{conn: conn} do
      account = create_account()
      {:ok, _show_live, html} = live(conn, ~p"/ledger/accounts/#{account}")

      assert html =~ "Show Account"
    end

    test "updates account within modal", %{conn: conn} do
      account = create_account()
      {:ok, show_live, _html} = live(conn, ~p"/ledger/accounts/#{account}")

      assert show_live
             |> element("a", "Edit")
             |> render_click() =~ "Edit Account"

      assert_patch(show_live, ~p"/ledger/accounts/#{account}/show/edit")

      assert show_live
             |> form("#account-form", set_account: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#account-form", set_account: @update_attrs)
             |> render_submit()

      wait_for_event(Conta.Commanded.Application, Conta.Event.AccountModified)

      assert_patch(show_live, ~p"/ledger/accounts/#{account}")

      html = render(show_live)
      assert html =~ "Account updated successfully"
    end
  end
end
