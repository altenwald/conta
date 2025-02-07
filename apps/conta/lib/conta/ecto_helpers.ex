defmodule Conta.EctoHelpers do
  @moduledoc """
  Helpers for Ecto.
  """
  import Ecto.Changeset

  @doc """
  If the field passed as parameter isn't empty (see `empty?/1`) then
  the fields passed as third parameter are required.
  """
  def validate_required_unless_empty(changeset, field, required_fields) do
    if empty?(get_field(changeset, field)) do
      changeset
    else
      validate_required(changeset, required_fields)
    end
  end

  @doc """
  Get true only if it's `nil`, or an empty list, or an empty map,
  or an empty string.
  """
  def empty?(nil), do: true
  def empty?([]), do: true
  def empty?(%{} = map) when map_size(map) == 0, do: true

  def empty?(str) when is_binary(str) do
    String.trim(str) == ""
  end

  @doc """
  Applied to a changeset (`Ecto.Changeset`) struct it's resolving to
  a schema struct or an error tuple.
  """
  def get_result(%Ecto.Changeset{valid?: true} = changeset) do
    apply_changes(changeset)
  end

  def get_result(changeset) do
    errors =
      traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts
          |> Keyword.get(String.to_existing_atom(key), key)
          |> to_string()
        end)
      end)

    {:error, errors}
  end
end
