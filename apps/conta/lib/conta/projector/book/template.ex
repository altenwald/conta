defmodule Conta.Projector.Book.Template do
  @moduledoc """
  Per-company invoice template: a logo plus optional custom CSS, injected into the
  invoice document (see `ContaWeb.InvoiceHTML` show template and the `/books/invoices/:id/css`
  endpoint) on top of the app's own stylesheet.

  `css` is free-form, but only the following classes are meant to be targeted - they
  carry no styling of their own, so overriding them doesn't fight the app's Tailwind/daisyUI
  classes:

    * `.invoice-title` - the "INVOICE" heading (font, size, color)
    * `.invoice-logo` - the company logo image
    * `.invoice-accent` - the invoice/product table header cells and the total highlight
    * `.invoice-comments` - the comments/payment details box

  Anything else (in particular Tailwind/daisyUI's own class names, like `.table` or `.btn`)
  is an implementation detail of the current markup and may change between releases.
  """

  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  typed_schema "book_templates" do
    field :nif, :string
    field :name, :string
    field :css, :string, default: ""
    field :logo, :binary
    field :logo_mime_type, :string

    timestamps()
  end

  @required_fields ~w[nif name]a
  @optional_fields ~w[css logo logo_mime_type]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:name)
  end
end
