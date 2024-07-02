defmodule Conta.Commanded.Serializer do
  @moduledoc """
  Ensuring to keep the information about the struct the element belongs
  when serialize/deserialize it.
  """

  @doc """
  Perform the serialization of the term.
  """
  defdelegate serialize(term), to: Commanded.Serialization.JsonSerializer

  @doc """
  For test purposes it uses only one param, no options. It's the same
  as `deserialize/2` adding `opts = []`.
  """
  def deserialize(binary), do: deserialize(binary, [])

  @doc """
  Convert the maps using the changeset (we assume they are Ecto schemas).
  """
  def deserialize("{}", []), do: %{}

  def deserialize(binary, config) when is_list(config) do
    deserialize(binary, Map.new(config))
  end

  def deserialize(binary, %{type: "Elixir.Conta.Aggregate." <> _}) do
    Jason.decode!(binary)
  end

  def deserialize(binary, %{type: type}) do
    struct = String.to_existing_atom(type)

    binary
    |> Jason.decode!()
    |> struct.changeset()
  end
end
