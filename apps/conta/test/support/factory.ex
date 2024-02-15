defmodule Conta.Factory do
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
end
