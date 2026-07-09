defmodule ContaWeb.ExpenseControllerTest do
  use ContaWeb.ConnCase

  import Conta.AutomatorFixtures

  alias Conta.AccountsFixtures

  setup do
    %{user: AccountsFixtures.insert(:user) |> AccountsFixtures.confirm_user()}
  end

  describe "GET /books/expenses/run/:automator_id" do
    test "runs the filter, injecting real expenses under the registry key", %{conn: conn, user: user} do
      filter =
        insert(:filter, %{
          type: :expense,
          output: :json,
          code: "return #expenses",
          params: [build(:filter_param, %{name: "expenses", type: :table})]
        })

      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/books/expenses/run/#{filter.id}")

      assert response(conn, 200) == "0"
    end
  end
end
