defmodule Conta.LedgerFixtures do
  use ExMachina.Ecto, repo: Conta.Repo

  def account_factory do
    id = Ecto.UUID.generate()

    %Conta.Projector.Ledger.Account{
      id: id,
      name: ["Assets"],
      ledger: "default",
      type: :assets,
      balances: [
        build(:balance, %{account_id: id, amount: 0})
      ]
    }
  end

  def balance_factory do
    %Conta.Projector.Ledger.Balance{
      currency: :EUR,
      amount: 10_00
    }
  end

  def entry_factory do
    id = Ecto.UUID.generate()

    %Conta.Projector.Ledger.Entry{
      id: id,
      on_date: ~D[2024-01-01],
      description: "Buy something",
      credit: 10_00,
      balance: 10_00,
      transaction_id: "f3093f1f-0a55-4356-b925-831035a8bca7",
      account_name: ~w[Assets Bank],
      related_account_name: ~w[Expenses Supermarket],
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end
end
