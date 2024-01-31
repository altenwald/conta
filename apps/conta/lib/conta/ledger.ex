defmodule Conta.Ledger do
  import Ecto.Query, only: [from: 2]
  alias Conta.Projector.Ledger.Account
  alias Conta.Projector.Ledger.Entry
  alias Conta.Repo

  def get_account_by_name(name) when is_list(name) do
    if account = Repo.get_by(Account, name: name) do
      {:ok, account}
    else
      {:error, :invalid_account_name}
    end
  end

  def list_accounts(type, depth \\ nil)

  def list_accounts(type, nil) do
    from(a in Account, where: a.type == ^type, preload: :balances)
    |> Repo.all()
  end

  def list_accounts(type, depth) when is_integer(depth) and depth > 0 do
    from(
      a in Account,
      where: a.type == ^type and fragment("array_length(?, 1)", a.name) == ^depth,
      preload: :balances
    )
    |> Repo.all()
  end

  def currencies do
    from(a in Account, group_by: a.currency, select: a.currency)
    |> Repo.all()
  end

  def list_accounts_by_parent(nil) do
    from(
      a in Account,
      where: is_nil(a.parent_id),
      order_by: a.name,
      preload: :balances
    )
    |> Repo.all()
  end

  def list_accounts_by_parent(parent) do
    from(
      a in Account,
      join: p in Account,
      on: a.parent_id == p.id,
      where: p.name == ^parent,
      order_by: a.name,
      preload: :balances
    )
    |> Repo.all()
  end

  def list_entries(account_name, limit) when is_list(account_name) and is_integer(limit) do
    if account = Repo.get_by(Account, name: account_name) do
      from(
        e in Entry,
        where: e.account_name == ^account_name,
        order_by: [desc: e.on_date, desc: e.inserted_at],
        limit: ^limit
      )
      |> Repo.all()
      |> Enum.map(&adjust_currency(&1, account.currency))
    end
  end

  def list_entries_by(text, limit) when is_integer(limit) do
    from(
      e in Entry,
      where: fragment("? ~ ?", e.description, ^text),
      or_where: fragment("ARRAY_TO_STRING(?, '.') ~ ?", e.account_name, ^text),
      limit: ^limit
    )
    |> Repo.all()
  end

  defp adjust_currency(%Entry{} = entry, currency) do
    %Entry{entry |
      credit: Money.new(entry.credit.amount, currency),
      debit: Money.new(entry.debit.amount, currency),
      balance: Money.new(entry.balance.amount, currency)
    }
  end
end
