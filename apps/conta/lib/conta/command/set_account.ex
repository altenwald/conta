defmodule Conta.Command.SetAccount do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  @typep currency() :: atom()

  typed_embedded_schema do
    field :ledger, :string
    field :id, :binary_id
    field :name, :string
    field :type, Ecto.Enum, values: ~w[assets liabilities equity revenue expenses]a
    field(:currency, Money.Ecto.Currency.Type) :: currency()
    field :notes, :string
    field :parent_name, :string, virtual: true
    field :simple_name, :string, virtual: true
  end

  @required_fields ~w[ledger name type currency]a
  @optional_fields ~w[id notes simple_name parent_name]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> populate_name()
    |> validate_required(@required_fields)
    |> validate_format(:simple_name, ~r/^[^.]+$/)
  end

  def to_command(changeset) do
    apply_changes(changeset)
  end

  defp populate_name(changeset) do
    simple_name = List.wrap(get_field(changeset, :simple_name))
    parent_name = String.split(get_field(changeset, :parent_name) || "", ".")
    put_change(changeset, :name, parent_name ++ simple_name)
  end

  def populate_account_virtual(%{"name" => name} = params) when is_list(name) do
    case List.pop_at(name, -1) do
      {simple_name, []} ->
        params
        |> Map.put("simple_name", simple_name)
        |> Map.delete("parent_name")

      {simple_name, parent_name} ->
        params
        |> Map.put("simple_name", simple_name)
        |> Map.put("parent_name", Enum.join(parent_name, "."))
    end
  end

  def populate_account_virtual(%{} = params), do: params
end
