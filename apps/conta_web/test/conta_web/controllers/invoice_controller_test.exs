defmodule ContaWeb.InvoiceControllerTest do
  use ContaWeb.ConnCase

  import Conta.AutomatorFixtures

  alias Conta.AccountsFixtures

  setup do
    %{user: AccountsFixtures.insert(:user) |> AccountsFixtures.confirm_user()}
  end

  describe "GET /books/invoices/run/:automator_id" do
    test "runs the filter, injecting real invoices under the registry key", %{conn: conn, user: user} do
      filter =
        insert(:filter, %{
          type: :invoice,
          output: :json,
          code: "return #invoices",
          params: [build(:filter_param, %{name: "invoices", type: :table})]
        })

      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/books/invoices/run/#{filter.id}")

      assert response(conn, 200) == "0"
    end
  end
end
