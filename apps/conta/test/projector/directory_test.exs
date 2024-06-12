defmodule Conta.Projector.DirectoryTest do
  use Conta.DataCase
  import Conta.DirectoryFixtures
  alias Conta.Projector.Directory

  setup do
    version =
      if pv = Repo.get(Directory.ProjectionVersion, "Conta.Projector.Directory") do
        pv.last_seen_version + 1
      else
        1
      end

    on_exit(fn ->
      Repo.delete_all(Directory.Contact)
      Repo.delete_all(Directory.ProjectionVersion)
    end)

    %{
      handler_name: "Conta.Projector.Directory",
      event_number: version
    }
  end

  describe "contact" do
    test "create successfully", metadata do
      event = %Conta.Event.ContactSet{
        company_nif: "A55666777",
        name: "John Smith",
        nif: "B11222333",
        address: "Smith street",
        postcode: "1111 AA",
        city: "City",
        state: "State",
        country: "NL",
      }

      assert :ok = Directory.handle(event, metadata)

      clauses = [company_nif: event.company_nif, nif: event.nif]
      assert %Directory.Contact{
        id: _,
        company_nif: "A55666777",
        name: "John Smith",
        nif: "B11222333",
        intracommunity: false,
        address: "Smith street",
        postcode: "1111 AA",
        city: "City",
        state: "State",
        country: "NL",
      } = Repo.get_by!(Directory.Contact, clauses)
    end

    test "update successfully", metadata do
      %Directory.Contact{
        id: id,
        company_nif: company_nif,
        nif: nif
      } = insert(:contact)

      event = %Conta.Event.ContactSet{
        company_nif: company_nif,
        name: "John Smith",
        nif: nif,
        address: "Smith street",
        postcode: "1111 AA",
        city: "City",
        state: "State",
        country: "NL",
      }

      assert :ok = Directory.handle(event, metadata)

      clauses = [company_nif: company_nif, nif: nif]
      assert %Directory.Contact{
        id: ^id,
        company_nif: ^company_nif,
        name: "John Smith",
        nif: ^nif,
        intracommunity: false,
        address: "Smith street",
        postcode: "1111 AA",
        city: "City",
        state: "State",
        country: "NL",
      } = Repo.get_by!(Directory.Contact, clauses)
    end

    test "remove successfully", metadata do
      %Directory.Contact{
        company_nif: company_nif,
        nif: nif
      } = insert(:contact)

      event = %Conta.Event.ContactRemoved{
        company_nif: company_nif,
        nif: nif
      }

      assert :ok = Directory.handle(event, metadata)

      clauses = [company_nif: company_nif, nif: nif]
      assert is_nil(Repo.get_by(Directory.Contact, clauses))
    end
  end
end
