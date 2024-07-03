defmodule Conta.Directory do
  import Conta.Commanded.Application
  import Ecto.Query, only: [from: 2]

  alias Conta.Command.RemoveContact
  alias Conta.Command.SetContact
  alias Conta.Projector.Directory.Contact
  alias Conta.Repo

  def list_contacts do
    from(c in Contact, order_by: c.name)
    |> Repo.all()
  end

  def get_contact_by_nif(nif), do: Repo.get_by(Contact, nif: nif)

  def get_contact(id), do: Repo.get(Contact, id)

  def contact_set(params) do
    with %_{} = command <- SetContact.changeset(params) do
      dispatch(command)
    end
  end

  def get_set_contact(id) when is_binary(id),
    do: get_set_contact(get_contact(id))

  def get_set_contact(nil), do: nil

  def get_set_contact(%Contact{} = contact) do
    %SetContact{
      company_nif: contact.company_nif,
      name: contact.name,
      nif: contact.nif,
      intracommunity: contact.intracommunity,
      address: contact.address,
      postcode: contact.postcode,
      city: contact.city,
      state: contact.state,
      country: contact.country
    }
  end

  def new_set_contact do
    %SetContact{
      company_nif: Application.get_env(:conta, :default_company_nif)
    }
  end

  def get_remove_contact(id) when is_binary(id),
    do: get_remove_contact(get_contact(id))

  def get_remove_contact(nil), do: nil

  def get_remove_contact(%Contact{} = contact) do
    %RemoveContact{
      company_nif: contact.company_nif,
      nif: contact.nif
    }
  end
end
