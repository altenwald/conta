defmodule Conta.MoneyHelpers do
  @moduledoc """
  Helpers for dealing with money (and Money library).
  """

  @type currency() :: atom()

  @doc """
  Check if the currency is valid.
  """
  def is_currency(currency) when is_atom(currency) do
    currency in Map.keys(Money.Currency.all())
  end

  def is_currency(currency) when is_binary(currency) do
    currencies =
      Money.Currency.all()
      |> Map.keys()
      |> Enum.map(&to_string/1)

    currency in currencies
  end

  @doc """
  Converts to `%Money{}` given a decimal, integer, or float.
  """
  def to_money(%Money{} = money), do: money
  def to_money(%Decimal{} = decimal), do: Money.parse!(decimal)
  def to_money(integer) when is_integer(integer), do: Money.new(integer)
  def to_money(float) when is_float(float), do: Money.parse!(float)

  @doc """
  Converts to `%Money{}` given a decimal, integer, or float and use the
  currency passed as second parameter.
  """
  def to_money(%Money{} = money, currency), do: %Money{money | currency: currency}
  def to_money(%Decimal{} = decimal, currency), do: Money.parse!(decimal, currency)
  def to_money(integer, currency) when is_integer(integer), do: Money.new(integer, currency)
  def to_money(float, currency) when is_float(float), do: Money.parse!(float, currency)
end

defimpl Jason.Encoder, for: Money do
  @moduledoc """
  The implementation for Jason of Money is required for serializing
  the events.
  """

  @doc false
  def encode(%Money{amount: amount}, _opts), do: Jason.encode!(amount)
end
