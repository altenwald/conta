defmodule Conta.LedgerContextTest do
  use Conta.DataCase
  import Conta.LedgerFixtures

  alias Conta.Ledger
  alias Conta.Projector.Ledger.Account
  alias Conta.Projector.Ledger.Entry
  alias Conta.Command.SetAccountTransaction

  describe "accounts" do
    test "list_accounts/0 returns all accounts with balances" do
      account = insert(:account)
      result = Ledger.list_accounts()
      assert Enum.any?(result, &(&1.id == account.id))
    end

    test "list_simple_accounts/0 returns accounts without preloading balances" do
      account = insert(:account)
      result = Ledger.list_simple_accounts()
      assert Enum.any?(result, &(&1.id == account.id))
    end

    test "list_accounts/1 filters by type" do
      insert(:account, %{name: ["Assets"], type: :assets})
      insert(:account, %{name: ["Expenses"], type: :expenses})
      result = Ledger.list_accounts(:assets)
      assert Enum.all?(result, &(&1.type == :assets))
    end

    test "list_accounts/2 filters by type and depth" do
      insert(:account, %{name: ["Assets"], type: :assets})
      account2 = insert(:account, %{name: ["Assets", "Bank"], type: :assets})
      result = Ledger.list_accounts(:assets, 2)
      assert length(result) == 1
      assert hd(result).id == account2.id
    end

    test "get_account!/1 returns account with balances" do
      account = insert(:account)
      loaded = Ledger.get_account!(account.id)
      assert loaded.id == account.id
      assert is_list(loaded.balances)
    end

    test "get_account/1 returns nil for unknown id" do
      assert nil == Ledger.get_account(Ecto.UUID.generate())
    end

    test "get_account_by_name/1 returns {:ok, account} when found" do
      account = insert(:account, %{name: ["Assets"]})
      assert {:ok, %Account{}} = Ledger.get_account_by_name(account.name)
    end

    test "get_account_by_name/1 returns error when not found" do
      assert {:error, :invalid_account_name} = Ledger.get_account_by_name(["NonExistent"])
    end

    test "list_ledgers/0 returns ledger names" do
      insert(:account, %{ledger: "default"})
      assert ["default"] = Ledger.list_ledgers()
    end

    test "list_currencies/0 returns configured currencies" do
      assert is_list(Ledger.list_currencies())
    end

    test "list_used_currencies/0 returns currencies from existing accounts" do
      insert(:account)
      result = Ledger.list_used_currencies()
      assert :EUR in result
    end

    test "search_accounts/1 finds accounts by name fragment" do
      insert(:account, %{name: ["Assets"]})
      result = Ledger.search_accounts("Assets")
      assert result != []
    end

    test "list_accounts_by_parent/1 with nil returns root accounts" do
      insert(:account, %{name: ["Assets"], type: :assets})
      result = Ledger.list_accounts_by_parent(nil)
      assert Enum.all?(result, &is_nil(&1.parent_id))
    end

    test "get_account_command!/1 returns SetAccount with virtual fields" do
      account = insert(:account, %{name: ["Assets"]})
      set_account = Ledger.get_account_command!(account.id)
      assert set_account.simple_name == "Assets"
      assert set_account.parent_name == nil
    end

    test "get_account_command!/1 with child account populates parent_name" do
      parent = insert(:account, %{name: ["Assets"]})
      child = insert(:account, %{name: ["Assets", "Bank"], parent_id: parent.id})
      set_account = Ledger.get_account_command!(child.id)
      assert set_account.simple_name == "Bank"
      assert set_account.parent_name == "Assets"
    end
  end

  describe "entries" do
    setup do
      account = insert(:account, %{name: ["Assets", "Bank"]})
      entry = insert(:entry, %{account_name: account.name})
      %{account: account, entry: entry}
    end

    test "get_entry!/1 returns entry by id", %{entry: entry} do
      assert %Entry{id: id} = Ledger.get_entry!(entry.id)
      assert id == entry.id
    end

    test "get_entry/1 returns nil for unknown id" do
      assert nil == Ledger.get_entry(Ecto.UUID.generate())
    end

    test "get_entries_by_transaction_id/1 returns entries for transaction", %{entry: entry} do
      result = Ledger.get_entries_by_transaction_id(entry.transaction_id)
      assert Enum.any?(result, &(&1.id == entry.id))
    end

    test "list_entries_by_account/2 returns entries for account", %{account: account, entry: entry} do
      result = Ledger.list_entries_by_account(account)
      assert Enum.any?(result, &(&1.id == entry.id))
    end

    test "list_entries_by_account/3 with page and dates_per_page", %{account: account, entry: entry} do
      result = Ledger.list_entries_by_account(account, 1, 10)
      assert Enum.any?(result, &(&1.id == entry.id))
    end

    test "list_entries/2 by account name with limit", %{account: account, entry: entry} do
      result = Ledger.list_entries(account.name, 10)
      assert Enum.any?(result, &(&1.id == entry.id))
    end

    test "search_entries_by_account/4 finds entries by description", %{account: account, entry: entry} do
      result = Ledger.search_entries_by_account(account, "something", 1, 10)
      assert Enum.any?(result, &(&1.id == entry.id))
    end

    test "list_entries_by/2 searches by text in description or account" do
      result = Ledger.list_entries_by("something", 10)
      assert is_list(result)
    end
  end

  describe "new_account_transaction/1" do
    test "returns a SetAccountTransaction with the given account" do
      sat = Ledger.new_account_transaction(["Assets", "Bank"])
      assert %SetAccountTransaction{} = sat
      assert sat.on_date == Date.utc_today()
      assert hd(sat.entries).account_name == ["Assets", "Bank"]
    end
  end

  describe "entry/7 helper" do
    test "builds a SetAccountTransaction.Entry struct" do
      entry = Ledger.entry("Dinner", ["Assets", "Cash"], 0, 50_00, nil, nil, nil)
      assert entry.description == "Dinner"
      assert entry.account_name == ["Assets", "Cash"]
      assert entry.debit == 50_00
    end
  end
end
