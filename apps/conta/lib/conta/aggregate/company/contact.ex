defmodule Conta.Aggregate.Company.Contact do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  @derive Jason.Encoder

  typed_embedded_schema do
    field :name, :string
    field :nif, :string
    field :intracommunity, :boolean, default: false
    field :address, :string
    field :postcode, :string
    field :city, :string
    field :state, :string
    field :country, :string
  end

  @required_fields ~w[name nif address postcode city country]a
  @optional_fields ~w[intracommunity state]a

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
