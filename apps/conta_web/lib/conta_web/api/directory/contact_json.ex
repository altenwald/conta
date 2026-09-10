defmodule ContaWeb.Api.Directory.ContactJSON do
  def index(%{contacts: contacts}) do
    Enum.map(contacts, &data/1)
  end

  def show(%{contact: contact}) do
    data(contact)
  end

  defp data(contact) do
    %{
      "id" => contact.id,
      "company_nif" => contact.company_nif,
      "name" => contact.name,
      "nif" => contact.nif,
      "intracommunity" => contact.intracommunity,
      "address" => contact.address,
      "postcode" => contact.postcode,
      "city" => contact.city,
      "state" => contact.state,
      "country" => contact.country,
      "emails" => contact.emails || []
    }
  end
end
