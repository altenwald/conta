defmodule Conta.Directory do
  import Conta.Commanded.Application
  import Ecto.Query, only: [from: 2]

  alias Conta.Command.SetContact
  alias Conta.Projector.Directory.Contact
  alias Conta.Repo

  def list_contacts do
    from(c in Contact, order_by: c.name)
    |> Repo.all()
  end

  def get_contact(nif), do: Repo.get_by(Contact, nif: nif)

  def contact_set(params) do
    with {:ok, command} <- SetContact.changeset(params) do
      dispatch(command)
    end
  end
end
