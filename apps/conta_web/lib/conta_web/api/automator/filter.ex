defmodule ContaWeb.Api.Automator.Filter do
  use ContaWeb, :api

  import Conta.Commanded.Application, only: [dispatch: 1]
  import Conta.EctoHelpers

  alias Conta.Automator
  alias Conta.Command.SetFilter

  @default_automator "automator"

  def index(conn, _params) do
    filters = Automator.list_filters()

    json(conn, %{
      "page" => 1,
      "entities_per_page" => min(length(filters), 20),
      "entities" =>
        for filter <- filters do
          %{
            "id" => filter.id,
            "name" => filter.name,
            "output" => filter.output,
            "language" => filter.language,
            "description" => filter.description,
            "code" => filter.code
          }
        end
    })
  end

  def show(conn, %{"id" => id}) do
    if filter = Automator.get_filter(id) do
      json(conn, filter)
    else
      conn
      |> put_status(:not_found)
      |> json("filter not found")
    end
  end

  def delete(conn, %{"id" => id}) do
    with filter when filter != nil <- Automator.get_filter(id),
         :ok <- dispatch(Automator.get_remove_filter(filter)) do
      json(conn, "ok")
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json("filter not found")

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
    set_filter(conn, %SetFilter{automator: @default_automator}, params)
  end

  def update(conn, %{"id" => id} = params) do
    set_filter(conn, Automator.get_set_filter(id), params)
  end

  defp set_filter(conn, nil, _params) do
    conn
    |> put_status(:not_found)
    |> json("filter not found")
  end

  defp set_filter(conn, set_filter, params) do
    changeset = SetFilter.changeset(set_filter, params)

    with true <- changeset.valid?,
         :ok <- dispatch(SetFilter.to_command(changeset)) do
      json(conn, "ok")
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

  defp maybe_disposition(conn, nil), do: conn

  defp maybe_disposition(conn, filename) do
    put_resp_header(conn, "content-disposition", "attachment; filename=#{filename}")
  end

  def run(conn, %{"id" => id} = params) do
    params = Map.delete(params, "id")

    with filter when filter != nil <- Automator.get_filter(id),
         params = Map.new(Automator.cast(filter, params)),
         {:ok, {mimetype, file, content}} <-
           Automator.run_filter(filter.automator, filter, params) do
      conn
      |> put_resp_content_type(mimetype)
      |> maybe_disposition(file)
      |> send_resp(200, content)
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json("not found")

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{"errors" => reason})
    end
  end
end
