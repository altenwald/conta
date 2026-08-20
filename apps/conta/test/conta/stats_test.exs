defmodule Conta.StatsTest do
  use Conta.DataCase, async: true

  alias Conta.Stats

  describe "patrimony graphs" do
    test "graph_patrimony/1 generates SVG without error" do
      svg = Stats.graph_patrimony(:EUR)
      assert is_binary(svg)
      assert String.starts_with?(svg, "<svg")
      assert svg =~ "<rect"
    end
  end

  describe "pnl graphs" do
    test "graph_pnl/2 generates SVG without error" do
      svg = Stats.graph_pnl(:EUR, 6)
      assert is_binary(svg)
      assert String.starts_with?(svg, "<svg")
      assert svg =~ "<rect"
    end
  end

  describe "income and outcome graphs" do
    test "graph_income/3 generates SVG without error" do
      svg = Stats.graph_income(:EUR, 4, 12)
      assert is_binary(svg)
      assert String.starts_with?(svg, "<svg")
    end

    test "graph_outcome/3 generates SVG without error" do
      svg = Stats.graph_outcome(:EUR, 4, 12)
      assert is_binary(svg)
      assert String.starts_with?(svg, "<svg")
    end
  end
end
