defmodule Conta.Aggregate.Company.PaymentMethod do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  typed_embedded_schema do
    field :name, :string
    field :slug, :string
    field :method, :string
    field :details, :string
    field :holder, :string
  end

  @required_fields ~w[name slug method]a
  @optional_fields ~w[details holder]a

  def new(params) do
    %__MODULE__{}
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> case do
      %Ecto.Changeset{valid?: true} = changeset ->
        changeset
        |> apply_changes()
        |> Map.from_struct()

      %Ecto.Changeset{valid?: false, errors: errors} ->
        {:error, errors}
    end
  end
end
