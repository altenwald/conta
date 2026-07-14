defmodule ContaWeb.ContactLiveTest do
  use ContaWeb.ConnCase, async: false

  import Commanded.Assertions.EventAssertions
  import Conta.DirectoryFixtures
  import Phoenix.LiveViewTest

  alias Conta.AccountsFixtures
  alias Conta.Command.SetCompany
  alias Conta.Command.SetContact
  alias Conta.Commanded.Application, as: CommandedApp
  alias Conta.Repo

  @company_nif "A55666777"

  @create_attrs %{
    name: "John Smith",
    nif: "B11222333",
    address: "Smith street",
    postcode: "1111 AA",
    city: "City",
    country: "NL"
  }
  @invalid_attrs %{name: "", nif: ""}

  setup %{conn: conn} do
    Repo.delete_all("directories_contacts")
    Repo.delete_all("users_tokens")
    Repo.delete_all("users")

    Application.put_env(:conta, :default_company_nif, @company_nif)

    :ok =
      CommandedApp.dispatch(%SetCompany{
        nif: @company_nif,
        name: "Great Company SA",
        address: "My Full Address",
        postcode: "28000",
        city: "Madrid",
        country: "ES"
      })

    user = AccountsFixtures.insert(:user) |> AccountsFixtures.confirm_user()

    conn = log_in_user(conn, user)
    %{conn: conn, user: user}
  end

  defp create_contact do
    Phoenix.PubSub.subscribe(Conta.PubSub, "event:contact_set")

    :ok =
      CommandedApp.dispatch(%SetContact{
        company_nif: @company_nif,
        nif: "B99999999",
        name: "Existing Contact",
        address: "Some street",
        postcode: "1111 AA",
        city: "City",
        country: "NL"
      })

    assert_receive {:contact_set, contact}, 1500
    contact
  end

  describe "Index" do
    test "lists all directory_contacts", %{conn: conn} do
      contact = insert(:contact, company_nif: @company_nif)

      {:ok, _index_live, html} = live(conn, ~p"/directories/contacts")

      assert html =~ "Contacts"
      assert html =~ contact.name
      assert html =~ contact.nif
    end

    test "saves new contact", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/directories/contacts")

      assert index_live
             |> element("a", "New Contact")
             |> render_click() =~ "New Contact"

      assert_patch(index_live, ~p"/directories/contacts/new")

      assert index_live
             |> form("#contact-form", set_contact: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#contact-form", set_contact: @create_attrs)
             |> render_submit()

      wait_for_event(Conta.Commanded.Application, Conta.Event.ContactSet)

      assert_patch(index_live, ~p"/directories/contacts")

      html = render(index_live)
      assert html =~ "Contact created successfully"
    end

    test "updates contact in listing", %{conn: conn} do
      contact = create_contact()
      update_attrs = %{@create_attrs | nif: contact.nif, name: "Jane Doe"}

      {:ok, index_live, _html} = live(conn, ~p"/directories/contacts")

      assert index_live
             |> element("#directory_contacts-#{contact.id} a[title='Edit']")
             |> render_click() =~ "Edit Contact"

      assert_patch(index_live, ~p"/directories/contacts/#{contact}/edit")

      assert index_live
             |> form("#contact-form", set_contact: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#contact-form", set_contact: update_attrs)
             |> render_submit()

      wait_for_event(Conta.Commanded.Application, Conta.Event.ContactSet)

      assert_patch(index_live, ~p"/directories/contacts")

      html = render(index_live)
      assert html =~ "Contact modified successfully"
    end

    test "deletes contact in listing", %{conn: conn} do
      contact = create_contact()
      {:ok, index_live, _html} = live(conn, ~p"/directories/contacts")

      assert index_live
             |> element("#directory_contacts-#{contact.id} a[title='Delete']")
             |> render_click()

      wait_for_event(Conta.Commanded.Application, Conta.Event.ContactRemoved)

      refute has_element?(index_live, "#directory_contacts-#{contact.id}")
    end
  end
end
