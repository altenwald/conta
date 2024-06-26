defmodule Conta.Projector.Directory do
  use Conta.Projector,
    application: Conta.Commanded.Application,
    repo: Conta.Repo,
    name: __MODULE__,
    consistency: Application.compile_env(:conta, :consistency, :eventual)

  alias Conta.Event.ContactRemoved
  alias Conta.Event.ContactSet
  alias Conta.Projector.Directory.Contact
  alias Conta.Repo

  project(%ContactSet{} = contact, _metadata, fn multi ->
    params = Map.from_struct(contact)
    changeset = Contact.changeset(params)
    update =
      params
      |> Map.delete(:nif)
      |> Map.delete(:company_nif)
      |> Enum.to_list()

    opts = [on_conflict: [set: update], conflict_target: [:nif, :company_nif]]
    Ecto.Multi.insert(multi, :contact, changeset, opts)
  end)

  project(%ContactRemoved{} = event, _metadata, fn multi ->
    clauses = Map.from_struct(event)
    if contact = Repo.get_by(Contact, clauses) do
      Ecto.Multi.delete(multi, :contact, contact)
    else
      multi
    end
  end)
end
