defmodule Conta.EctoHelpers do
  import Ecto.Changeset

  def validate_if_required(changeset, field, required_fields) do
    if empty?(get_field(changeset, field)) do
      changeset
    else
      validate_required(changeset, required_fields)
    end
  end

  def empty?(nil), do: true
  def empty?(str) when is_binary(str) do
    String.trim(str) == ""
  end

  def traverse_errors(%Ecto.Changeset{valid?: true} = changeset) do
    apply_changes(changeset)
  end

  def traverse_errors(changeset) do
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
