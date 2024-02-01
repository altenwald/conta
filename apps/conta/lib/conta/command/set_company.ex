defmodule Conta.Command.SetCompany do
  use TypedEctoSchema

  @primary_key false

  typed_embedded_schema do
    field :nif, :string
    field :name, :string
    field :address, :string
    field :postcode, :string
    field :city, :string
    field :state, :string
    field :country, :string
  end
end
