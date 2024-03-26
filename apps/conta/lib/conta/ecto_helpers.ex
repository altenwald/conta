defmodule Conta.EctoHelpers do
  import Ecto.Changeset

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
