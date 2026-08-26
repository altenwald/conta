defmodule Mix.Tasks.Conta.RebuildProjection do
  @shortdoc "Rebuilds one or all projections from EventStore"
  @moduledoc """
  Rebuilds Ecto read model projections by replaying events from the EventStore.

  ## Examples

      $ mix conta.rebuild_projection ledger
      $ mix conta.rebuild_projection book
      $ mix conta.rebuild_projection stats
      $ mix conta.rebuild_projection all

  """
  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    target =
      case args do
        [] -> :all
        [name | _] -> name
      end

    Conta.Projector.Rebuild.rebuild(target)
  end
end
