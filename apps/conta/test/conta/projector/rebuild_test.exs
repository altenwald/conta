defmodule Conta.Projector.RebuildTest do
  use Conta.DataCase
  alias Conta.Projector.Rebuild

  test "available_projectors/0 returns list of supported projector atoms" do
    projectors = Rebuild.available_projectors()
    assert is_list(projectors)
    assert :ledger in projectors
    assert :book in projectors
    assert :stats in projectors
    assert :directory in projectors
    assert :reconciliation in projectors
    assert :automator in projectors
  end

  test "rebuild/2 accepts target projector and runs without errors" do
    # When no events are present or with existing projections, rebuild should complete successfully
    assert :ok == Rebuild.rebuild(:directory, log: false)
  end
end
