defmodule Conta.Stats do
  import Ecto.Query, only: [from: 2]
  alias Conta.Projector.Stats.Patrimony
  alias Conta.Repo

  def list_patrimony(nil) do
    from(
      p in Patrimony,
      order_by: [desc: p.year, desc: p.month],
      limit: 6
    )
    |> Repo.all()
    |> Enum.map(&adjust_currency/1)
  end

  def list_patrimony(currency) when is_atom(currency) do
    from(
      p in Patrimony,
      where: p.currency == ^currency,
      order_by: [desc: p.year, desc: p.month],
      limit: 6
    )
    |> Repo.all()
    |> Enum.map(&adjust_currency/1)
  end

  defp adjust_currency(%Patrimony{currency: currency, amount: amount, balance: balance} = patrimony) do
    %Patrimony{patrimony |
      amount: Money.new(amount.amount, currency),
      balance: Money.new(balance.amount, currency)
    }
  end
end
