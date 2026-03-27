defmodule Conta.DirectoryTest do
  use Conta.DataCase
  import Conta.DirectoryFixtures

  alias Conta.Directory
  alias Conta.Projector.Directory.Contact

  describe "contacts" do
    test "list_contacts/0 returns all contacts" do
      contact = insert(:contact)
      result = Directory.list_contacts()
      assert Enum.any?(result, &(&1.id == contact.id))
    end

    test "get_contact/1 returns the contact" do
      contact = insert(:contact)
      assert %Contact{id: id} = Directory.get_contact(contact.id)
      assert id == contact.id
    end

    test "get_contact/1 returns nil for unknown id" do
      assert nil == Directory.get_contact(Ecto.UUID.generate())
    end

    test "get_contact_by_nif/1 returns contact by nif" do
      contact = insert(:contact)
      assert %Contact{nif: nif} = Directory.get_contact_by_nif(contact.nif)
      assert nif == contact.nif
    end

    test "get_contact_by_nif/1 returns nil for unknown nif" do
      assert nil == Directory.get_contact_by_nif("UNKNOWN_NIF")
    end

    test "get_set_contact/1 with id returns SetContact command" do
      contact = insert(:contact)
      set_contact = Directory.get_set_contact(contact.id)
      assert set_contact.nif == contact.nif
      assert set_contact.name == contact.name
    end

    test "get_set_contact/1 with nil returns nil" do
      assert nil == Directory.get_set_contact(nil)
    end

    test "get_set_contact/1 with Contact struct" do
      contact = insert(:contact)
      set_contact = Directory.get_set_contact(contact)
      assert set_contact.nif == contact.nif
    end

    test "new_set_contact/0 returns a SetContact with default company_nif" do
      set_contact = Directory.new_set_contact()
      assert %Conta.Command.SetContact{} = set_contact
    end

    test "get_remove_contact/1 with id returns RemoveContact command" do
      contact = insert(:contact)
      remove = Directory.get_remove_contact(contact.id)
      assert remove.nif == contact.nif
      assert remove.company_nif == contact.company_nif
    end

    test "get_remove_contact/1 with nil returns nil" do
      assert nil == Directory.get_remove_contact(nil)
    end
  end
end
