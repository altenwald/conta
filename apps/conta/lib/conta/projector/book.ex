defmodule Conta.Projector.Book do
  use Commanded.Projections.Ecto,
    application: Conta.Commanded.Application,
    repo: Conta.Repo,
    name: __MODULE__

  alias Conta.Event.InvoiceCreated
  alias Conta.Projector.Book.Invoice

  project(%InvoiceCreated{} = account, _metadata, fn multi ->
    params =
      account
      |> Map.from_struct()
      |> Map.put(:payment_method, process_one(account.payment_method))
      |> Map.put(:client, process_one(account.client))
      |> Map.put(:company, process_one(account.company))
      |> Map.put(:details, process_many(account.details))

    changeset = Invoice.changeset(params)
    Ecto.Multi.insert(multi, :invoice, changeset)
  end)

  defp process_one(nil), do: nil
  defp process_one(%_{} = payment), do: Map.from_struct(payment)

  defp process_many([]), do: []
  defp process_many(nil), do: []
  defp process_many(elements), do: Enum.map(elements, &Map.from_struct/1)
end
