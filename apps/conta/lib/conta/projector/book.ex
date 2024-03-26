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

  project(%InvoiceCreated{} = invoice, _metadata, fn multi ->
    invoice_number =
      invoice.invoice_number
      |> to_string()
      |> String.pad_leading(5, "0")
      |> then(&"#{invoice.invoice_date.year}-#{&1}")

    params =
      invoice
      |> Map.from_struct()
      |> Map.put(:invoice_number, invoice_number)
      |> Map.put(:payment_method, Map.from_struct(invoice.payment_method))
      |> Map.put(:client, Map.from_struct(invoice.client))
      |> Map.put(:company, Map.from_struct(invoice.company))
      |> Map.update!(:details, fn details -> Enum.map(details, &Map.from_struct/1) end)

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
