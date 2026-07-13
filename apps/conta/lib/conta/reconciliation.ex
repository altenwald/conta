defmodule Conta.Reconciliation do
  @moduledoc """
  Context for bank-statement reconciliation: listing and looking up
  match rules and pending movements from the read model.
  """

  import Ecto.Query, only: [from: 2]

  alias Conta.Projector.Reconciliation.MatchRule
  alias Conta.Projector.Reconciliation.Movement
  alias Conta.Repo

  def list_match_rules do
    from(r in MatchRule, order_by: r.position)
    |> Repo.all()
  end

  def get_match_rule!(id) do
    Repo.get!(MatchRule, id)
  end

  def list_movements do
    from(m in Movement, order_by: m.on_date)
    |> Repo.all()
  end

  def get_movement!(id) do
    Repo.get!(Movement, id)
  end
end
