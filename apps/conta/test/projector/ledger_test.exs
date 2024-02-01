defmodule Conta.Projector.LedgerTest do
  use Conta.DataCase
  alias Conta.Projector.Ledger

  setup do
    version =
      if pv = Repo.get(Ledger.ProjectionVersion, "Conta.Projector.Ledger") do
        pv.last_seen_version + 1
      else
        1
      end

    on_exit(fn ->
      Repo.delete_all(Ledger.Entry)
      Repo.delete_all(Ledger.Balance)
      Repo.delete_all(Ledger.Account)
      Repo.delete_all(Ledger.ProjectionVersion)
    end)

    %{
      handler_name: "Conta.Projector.Ledger",
      event_number: version
    }
  end

  describe "account" do
    test "create account", metadata do
      event =
        %Conta.Event.AccountSet{
          name: ["Assets"],
          ledger: "default",
          type: :assets,
          notes: "hello there!"
        }

      assert :ok == Conta.Projector.Ledger.handle(event, metadata)

      assert %Conta.Projector.Ledger.Account{
        id: _,
        name: ["Assets"],
        ledger: "default",
        type: :assets,
        notes: "hello there!"
      } = Repo.get_by!(Conta.Projector.Ledger.Account, name: ["Assets"])
    end

    test "update account", metadata do
      account =
        %Conta.Projector.Ledger.Account{
          name: ["Expenses"],
          ledger: "default",
          type: :expenses,
          notes: "global expenses account"
        }

      account = Repo.insert!(account)

      event =
        %Conta.Event.AccountSet{
          name: ["Expenses"],
          ledger: "default",
          type: :expenses,
          notes: "no so global expenses account"
        }

      assert :ok == Conta.Projector.Ledger.handle(event, metadata)

      assert %Conta.Projector.Ledger.Account{
        id: _,
        name: ["Expenses"],
        ledger: "default",
        type: :expenses,
        notes: "no so global expenses account"
      } = Repo.get!(Conta.Projector.Ledger.Account, account.id)
    end
  end
end
