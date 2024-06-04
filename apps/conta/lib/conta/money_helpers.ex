defmodule Conta.MoneyHelpers do
  @moduledoc """
  Helpers for dealing with money (and Money library).
  """

  @doc """
  Converts to `%Money{}` given a decimal, integer, or float.
  """
  def to_money(%Money{} = money), do: money
  def to_money(%Decimal{} = decimal), do: Money.parse!(decimal)
  def to_money(integer) when is_integer(integer), do: Money.new(integer)
  def to_money(float) when is_float(float), do: Money.parse!(float)
end

defimpl Jason.Encoder, for: Money do
  @moduledoc """
  The implementation for Jason of Money is required for serializing
  the events.
  """

  @doc false
  def encode(%Money{amount: amount}, _opts), do: Jason.encode!(amount)
end
