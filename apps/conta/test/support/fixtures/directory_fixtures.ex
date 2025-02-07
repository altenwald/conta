defmodule Conta.DirectoryFixtures do
  use ExMachina.Ecto, repo: Conta.Repo

  def contact_factory do
    %Conta.Projector.Directory.Contact{
      company_nif: sequence(:company_nif, &"NL0039004#{&1}B64", start_at: 100),
      name: sequence(:name, ~w[Alice Bob Chloe Dan Emily Frank Gal Hank Isabel Jack]),
      nif: sequence(:nif, &"A#{&1}", start_at: 2002),
      intracommunity: false,
      address: "My street",
      postcode: "1111 AA",
      city: "City",
      country: "NL"
    }
  end
end
