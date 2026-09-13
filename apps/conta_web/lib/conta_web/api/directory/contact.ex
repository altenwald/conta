defmodule ContaWeb.Api.Directory.Contact do
  use ContaWeb, :api

  import Conta.Commanded.Application, only: [dispatch: 1, dispatch: 2]
  import Conta.EctoHelpers

  alias Conta.Command.SetContact
  alias Conta.Directory

  def index(conn, _params) do
    contacts = Directory.list_contacts()
    render(conn, contacts: contacts)
  end

  def show(conn, %{"id" => id}) do
    default_company_nif = Application.get_env(:conta, :default_company_nif)

    case Directory.get_contact(id) || Directory.get_contact_by_nif(default_company_nif, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{"errors" => %{"id" => "contact not found"}})

      contact ->
        render(conn, contact: contact)
    end
  end

  def delete(conn, %{"id" => id}) do
    default_company_nif = Application.get_env(:conta, :default_company_nif)

    with contact when contact != nil <-
           Directory.get_contact(id) || Directory.get_contact_by_nif(default_company_nif, id),
         :ok <- dispatch(Directory.get_remove_contact(contact)) do
      json(conn, "ok")
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{"errors" => %{"id" => "contact not found"}})

      {:error, reason} when is_atom(reason) ->
        conn
        |> put_status(:bad_request)
        |> json(%{"errors" => %{"dispatch" => [reason]}})

      {:error, errors} when is_map(errors) ->
        conn
        |> put_status(:bad_request)
        |> json(%{"errors" => errors})
    end
  end

  def create(conn, params) do
    company_nif = get_company_nif(params)
    id = resolve_contact_id(params, company_nif)

    params =
      params
      |> Map.put("id", id)
      |> Map.put_new("company_nif", company_nif)

    changeset = SetContact.changeset(%SetContact{}, params)

    if changeset.valid? do
      dispatch_create(conn, changeset)
    else
      {:error, errors} = get_result(changeset)

      conn
      |> put_status(:bad_request)
      |> json(%{"errors" => errors})
    end
  end

  defp dispatch_create(conn, changeset) do
    command = SetContact.to_command(changeset)

    case dispatch(command, returning: :execution_result) do
      {:ok, %Commanded.Commands.ExecutionResult{events: events}} ->
        contact_set = Enum.find(events, &match?(%Conta.Event.ContactSet{}, &1))

        conn
        |> put_status(:created)
        |> json(%{
          "id" => (contact_set && contact_set.id) || command.id,
          "nif" => (contact_set && contact_set.nif) || command.nif
        })

      {:error, reason} when is_atom(reason) ->
        conn
        |> put_status(:bad_request)
        |> json(%{"errors" => %{"dispatch" => [reason]}})

      {:error, errors} when is_map(errors) ->
        conn
        |> put_status(:bad_request)
        |> json(%{"errors" => errors})
    end
  end

  defp get_company_nif(params) do
    params["company_nif"] || params[:company_nif] ||
      Application.get_env(:conta, :default_company_nif)
  end

  defp resolve_contact_id(params, company_nif) do
    case params["id"] || params[:id] do
      id when is_binary(id) and id != "" ->
        id

      _ ->
        nif = params["nif"] || params[:nif]
        existing = if nif, do: Directory.get_contact_by_nif(company_nif, nif)
        if existing, do: existing.id, else: Ecto.UUID.generate()
    end
  end

  def update(conn, %{"id" => id} = params) do
    default_company_nif = Application.get_env(:conta, :default_company_nif)

    case Directory.get_contact(id) || Directory.get_contact_by_nif(default_company_nif, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{"errors" => %{"id" => "contact not found"}})

      contact ->
        set_contact = Directory.get_set_contact(contact)
        params = Map.put_new(params, "id", contact.id)
        changeset = SetContact.changeset(set_contact, params)

        with true <- changeset.valid?,
             command = SetContact.to_command(changeset),
             {:ok, %Commanded.Commands.ExecutionResult{events: events}} <-
               dispatch(command, returning: :execution_result) do
          contact_set = Enum.find(events, &match?(%Conta.Event.ContactSet{}, &1))

          conn
          |> put_status(:ok)
          |> json(%{
            "id" => (contact_set && contact_set.id) || command.id,
            "nif" => (contact_set && contact_set.nif) || command.nif
          })
        else
          false ->
            {:error, errors} = get_result(changeset)

            conn
            |> put_status(:bad_request)
            |> json(%{"errors" => errors})

          {:error, reason} when is_atom(reason) ->
            conn
            |> put_status(:bad_request)
            |> json(%{"errors" => %{"dispatch" => [reason]}})

          {:error, errors} when is_map(errors) ->
            conn
            |> put_status(:bad_request)
            |> json(%{"errors" => errors})
        end
    end
  end
end
