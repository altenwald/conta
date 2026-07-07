defmodule Conta.AutomatorFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Conta.Automator` context.
  """
  use ExMachina.Ecto, repo: Conta.Repo

  def shortcut_factory do
    %Conta.Projector.Automator.Shortcut{
      name: "credit cash",
      automator: "automator",
      description: "write spend cash down",
      code: "-- Lua code\n",
      language: :lua
    }
  end

  def shortcut_param_factory do
    %Conta.Projector.Automator.Param{
      name: "amount",
      type: :money
    }
  end

  def filter_factory do
    %Conta.Projector.Automator.Filter{
      name: "unpaid invoices",
      automator: "automator",
      description: "list unpaid invoices",
      type: :all,
      output: :json,
      code: "-- Lua code\n",
      language: :lua
    }
  end

  def filter_param_factory do
    %Conta.Projector.Automator.Param{
      name: "from_date",
      type: :date
    }
  end
end
