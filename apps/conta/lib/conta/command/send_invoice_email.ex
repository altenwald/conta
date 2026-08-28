defmodule Conta.Command.SendInvoiceEmail do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false

  typed_embedded_schema do
    field :id, :binary_id
    field :invoice_id, :binary_id
    field :company_nif, :string
    field :to, :string
    field :subject, :string
    field :body, :string
    field :sent_at, :utc_datetime_usec
  end

  @required_fields ~w[invoice_id company_nif to subject]a
  @optional_fields ~w[id body sent_at]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_format(:to, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> maybe_generate_id()
    |> maybe_set_sent_at()
  end

  def to_command(changeset) do
    apply_changes(changeset)
  end

  defp maybe_generate_id(changeset) do
    case get_field(changeset, :id) do
      nil -> put_change(changeset, :id, Ecto.UUID.generate())
      _id -> changeset
    end
  end

  defp maybe_set_sent_at(changeset) do
    case get_field(changeset, :sent_at) do
      nil -> put_change(changeset, :sent_at, DateTime.utc_now())
      _sent_at -> changeset
    end
  end
end
