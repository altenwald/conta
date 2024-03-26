defmodule ContaWeb.EntryLiveTest do
  use ContaWeb.ConnCase

  import Phoenix.LiveViewTest
  import Conta.LedgerFixtures

  @create_attrs %{}
  @update_attrs %{}
  @invalid_attrs %{}

  defp create_entry(_) do
    entry = entry_fixture()
    %{entry: entry}
  end

  describe "Index" do
    setup [:create_entry]

    test "lists all ledger_entries", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/ledger_entries")

      assert html =~ "Listing Ledger entries"
    end

    test "saves new entry", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/ledger_entries")

      assert index_live |> element("a", "New Entry") |> render_click() =~
               "New Entry"

      assert_patch(index_live, ~p"/ledger_entries/new")

      assert index_live
             |> form("#entry-form", entry: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#entry-form", entry: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/ledger_entries")

      html = render(index_live)
      assert html =~ "Entry created successfully"
    end

    test "updates entry in listing", %{conn: conn, entry: entry} do
      {:ok, index_live, _html} = live(conn, ~p"/ledger_entries")

      assert index_live |> element("#ledger_entries-#{entry.id} a", "Edit") |> render_click() =~
               "Edit Entry"

      assert_patch(index_live, ~p"/ledger_entries/#{entry}/edit")

      assert index_live
             |> form("#entry-form", entry: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#entry-form", entry: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/ledger_entries")

      html = render(index_live)
      assert html =~ "Entry updated successfully"
    end

    test "deletes entry in listing", %{conn: conn, entry: entry} do
      {:ok, index_live, _html} = live(conn, ~p"/ledger_entries")

      assert index_live |> element("#ledger_entries-#{entry.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#ledger_entries-#{entry.id}")
    end
  end

  describe "Show" do
    setup [:create_entry]

    test "displays entry", %{conn: conn, entry: entry} do
      {:ok, _show_live, html} = live(conn, ~p"/ledger_entries/#{entry}")

      assert html =~ "Show Entry"
    end

    test "updates entry within modal", %{conn: conn, entry: entry} do
      {:ok, show_live, _html} = live(conn, ~p"/ledger_entries/#{entry}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Entry"

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
