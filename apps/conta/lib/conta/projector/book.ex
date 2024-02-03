defmodule Conta.Projector.Book do
  use Commanded.Projections.Ecto,
    application: Conta.Commanded.Application,
    repo: Conta.Repo,
    name: __MODULE__

  alias Conta.Event.InvoiceCreated
  alias Conta.Event.TemplateSet
  alias Conta.Projector.Book.Invoice
  alias Conta.Projector.Book.Template

  project(%InvoiceCreated{} = account, _metadata, fn multi ->
    params = Map.from_struct(account)
    changeset = Invoice.changeset(params)
    Ecto.Multi.insert(multi, :invoice, changeset)
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
