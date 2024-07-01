defmodule Conta.Command.SetExpense do
  use TypedEctoSchema
  import Ecto.Changeset
  alias Conta.Domain.Expense

  @primary_key false

  typed_embedded_schema do
    field :action, Ecto.Enum, values: ~w[insert update]a
    field :name, :string
    field :nif, :string
    field :provider_nif, :string
    field :invoice_number, :string
    field :invoice_date, :date
    field :paid_date, :date
    field :due_date, :date
    field :category, Ecto.Enum, values: Expense.categories()
    field :subtotal_price, :decimal
    field :tax_price, :decimal
    field :total_price, :decimal
    field :currency, :string
    field :comments, :string
    field :payment_method, :string
    embeds_many :attachments, Attachment, on_replace: :delete do
      field :name, :string
      field :file, :binary
      field :mimetype, :string
      field :size, :integer
      timestamps()
    end
  end

  @required_fields ~w[action nif provider_nif invoice_number invoice_date category subtotal_price tax_price total_price currency payment_method]a
  @optional_fields ~w[name paid_date due_date comments]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> cast_embed(:attachments, with: &changeset_attachments/2)
    |> validate_required(@required_fields)
  end

  @required_fields ~w[name file mimetype size]a
  @optional_fields ~w[inserted_at updated_at]a

  @doc false
  def changeset_attachments(model, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  def to_command(changeset) do
    apply_changes(changeset)
  end
end
