defmodule ContaWeb.ShortcutLiveTest do
  use ContaWeb.ConnCase

  import Phoenix.LiveViewTest
  import Conta.AutomatorFixtures
  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Automator
  alias Conta.AccountsFixtures

  setup do
    user = AccountsFixtures.insert(:user) |> AccountsFixtures.confirm_user()
    %{user: user}
  end

  describe "Index" do
    test "lists all shortcuts", %{conn: conn, user: user} do
      _shortcut = insert(:shortcut, %{name: "my shortcut"})
      conn = log_in_user(conn, user)

      {:ok, _index_live, html} = live(conn, ~p"/automation/shortcuts")

      assert html =~ "my shortcut"
    end

    test "deletes shortcut in listing", %{conn: conn, user: user} do
      shortcut = insert(:shortcut, %{name: "to be removed"})
      # The shortcut fixture only writes to the read model. The RemoveShortcut
      # command validates against the event-sourced aggregate, so the
      # aggregate needs to know about this shortcut first (this updates the
      # same projected row, since the projector matches by name+automator).
      :ok = dispatch(Automator.get_set_shortcut(shortcut))
      conn = log_in_user(conn, user)

      {:ok, index_live, _html} = live(conn, ~p"/automation/shortcuts")

      assert index_live
             |> element("#automator_shortcuts-#{shortcut.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#automator_shortcuts-#{shortcut.id}")
    end
  end
end
