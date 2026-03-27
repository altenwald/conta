defmodule Conta.MoneyHelpersTest do
  use ExUnit.Case, async: true

  import Conta.MoneyHelpers

  describe "is_currency/1" do
    test "atom :EUR is valid" do
      assert is_currency(:EUR)
    end

    test "atom :USD is valid" do
      assert is_currency(:USD)
    end

    test "unknown atom is invalid" do
      refute is_currency(:NOPE)
    end

    test "binary \"EUR\" is valid" do
      assert is_currency("EUR")
    end

    test "binary \"USD\" is valid" do
      assert is_currency("USD")
    end

    test "unknown binary is invalid" do
      refute is_currency("NOPE")
    end
  end

  describe "to_money/1" do
    test "passes Money struct through unchanged" do
      money = Money.new(100, :EUR)
      assert ^money = to_money(money)
    end

    test "converts integer (cents) to Money" do
      assert %Money{amount: 100} = to_money(100)
    end

    test "converts float to Money" do
      assert %Money{amount: 100} = to_money(1.00)
    end

    test "converts Decimal to Money" do
      assert %Money{amount: 100} = to_money(Decimal.new("1.00"))
    end
  end

  describe "to_money/2 with currency" do
    test "changes currency on an existing Money struct" do
      money = Money.new(500, :EUR)
      result = to_money(money, :USD)
      assert %Money{amount: 500, currency: :USD} = result
    end

    test "converts integer with explicit currency" do
      assert %Money{amount: 2500, currency: :GBP} = to_money(2500, :GBP)
    end

    test "converts float with explicit currency" do
      assert %Money{amount: 2500, currency: :GBP} = to_money(25.00, :GBP)
    end

    test "converts Decimal with explicit currency" do
      assert %Money{amount: 2500, currency: :GBP} = to_money(Decimal.new("25.00"), :GBP)
    end
  end
end
