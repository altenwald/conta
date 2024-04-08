defmodule Conta.Projector.Book do
  use Commanded.Projections.Ecto,
    application: Conta.Commanded.Application,
    repo: Conta.Repo,
    name: __MODULE__

  alias Conta.Event.InvoiceCreated
  alias Conta.Event.PaymentMethodSet
  alias Conta.Event.TemplateSet
  alias Conta.Projector.Book.Invoice
  alias Conta.Projector.Book.PaymentMethod
  alias Conta.Projector.Book.Template

  defp to_integer(i) when is_integer(i), do: i

  defp to_integer(f) when is_float(f), do: ceil(f * 100)

  defp to_integer(str) when is_binary(str) do
    str
    |> Decimal.parse()
    |> then(fn {decimal, ""} -> to_integer(decimal) end)
  end

  defp to_integer(decimal) when is_struct(decimal, Decimal) do
    decimal
    |> Decimal.mult(100)
    |> Decimal.round(0, :ceiling)
    |> Decimal.to_integer()
  end

  project(%InvoiceCreated{} = invoice, _metadata, fn multi ->
    invoice_date = Date.from_iso8601!(invoice.invoice_date)
    invoice_number =
      invoice.invoice_number
      |> to_string()
      |> String.pad_leading(5, "0")
      |> then(&"#{invoice_date.year}-#{&1}")

    params =
      invoice
      |> Map.from_struct()
      |> Map.put(:invoice_number, invoice_number)
      |> Map.update!(:subtotal_price, &to_integer/1)
      |> Map.update!(:tax_price, &to_integer/1)
      |> Map.update!(:total_price, &to_integer/1)
      |> Map.update!(:details, fn details ->
        for detail <- details do
          detail
          |> Map.update!(:base_price, &to_integer/1)
          |> Map.update!(:tax_price, &to_integer/1)
          |> Map.update!(:total_price, &to_integer/1)
        end
      end)

    changeset = Invoice.changeset(params)
    Ecto.Multi.insert(multi, :invoice, changeset)
  end)

  project(%PaymentMethodSet{} = payment_method, _metadata, fn multi ->
    changeset =
      payment_method
      |> Map.from_struct()
      |> PaymentMethod.changeset()

    update =
      payment_method
      |> Map.from_struct()
      |> Map.delete(:nif)
      |> Map.delete(:slug)
      |> Enum.to_list()

    opts = [on_conflict: [set: update], conflict_target: [:nif, :slug]]
    Ecto.Multi.insert(multi, :template, changeset, opts)
  end)

  project(%TemplateSet{} = template, _metadata, fn multi ->
    changeset =
      template
      |> Map.from_struct()
      |> translate_logo()
      |> Template.changeset()

    update =
      template
      |> Map.from_struct()
      |> translate_logo()
      |> Map.delete(:name)
      |> Enum.to_list()

    opts = [on_conflict: [set: update], conflict_target: [:name]]
    Ecto.Multi.insert(multi, :template, changeset, opts)
  end)

  defp translate_logo(%{logo: nil} = params), do: params

  defp translate_logo(%{logo: logo} = params) do
    Map.put(params, :logo, Base.decode64!(logo))
  end
end
