defmodule ContaWeb.FilterLiveTest do
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
    test "lists all filters", %{conn: conn, user: user} do
      _filter = insert(:filter, %{name: "my filter"})
      conn = log_in_user(conn, user)

      {:ok, _index_live, html} = live(conn, ~p"/automation/filters")

      assert html =~ "my filter"
    end

    test "deletes filter in listing", %{conn: conn, user: user} do
      filter = insert(:filter, %{name: "to be removed"})
      # The filter fixture only writes to the read model. The RemoveFilter
      # command validates against the event-sourced aggregate, so the
      # aggregate needs to know about this filter first (this updates the
      # same projected row, since the projector matches by name+automator).
      :ok = dispatch(Automator.get_set_filter(filter))
      conn = log_in_user(conn, user)

      {:ok, index_live, _html} = live(conn, ~p"/automation/filters")

      assert index_live
             |> element("#automator_filters-#{filter.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#automator_filters-#{filter.id}")
    end
  end
end
