defmodule ContaWeb.Api.Automator.Shortcut do
  use ContaWeb, :api

  import Conta.Commanded.Application, only: [dispatch: 1]
  import Conta.EctoHelpers

  alias Conta.Automator
  alias Conta.Command.SetShortcut

  def index(conn, _params) do
    shortcuts = Automator.list_shortcuts()

    if shortcuts != [] do
      json(conn, %{
        "page" => 1,
        "entities_per_page" => length(shortcuts),
        "entities" =>
          for shortcut <- shortcuts do
            %{
              "id" => shortcut.id,
              "name" => shortcut.name,
              "langauge" => shortcut.language,
              "description" => shortcut.description,
              "code" => shortcut.code
            }
          end
      })
    else
      conn
      |> put_status(:not_found)
      |> json("empty page")
    end
  end

  def show(conn, %{"id" => id}) do
    if shortcut = Automator.get_shortcut(id) do
      json(conn, shortcut)
    else
      conn
      |> put_status(:not_found)
      |> json("shortcut not found")
    end
  end

  def delete(conn, %{"id" => id}) do
    with shortcut when shortcut != nil <- Automator.get_shortcut(id),
         :ok <- dispatch(Automator.get_remove_shortcut(shortcut)) do
      json(conn, "ok")
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json("shortcut not found")

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
    set_shortcut(conn, %SetShortcut{}, params)
  end

  def update(conn, %{"id" => id} = params) do
    set_shortcut(conn, Automator.get_set_shortcut(id), params)
  end

  defp set_shortcut(conn, nil, _params) do
    conn
    |> put_status(:not_found)
    |> json("shortcut not found")
  end

  defp set_shortcut(conn, set_shortcut, params) do
    changeset = SetShortcut.changeset(set_shortcut, params)

    with true <- changeset.valid?,
         :ok <- dispatch(SetShortcut.to_command(changeset)) do
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

  def run(conn, %{"id" => id} = params) do
    params = Map.delete(params, "id")

    with shortcut when shortcut != nil <- Automator.get_shortcut(id),
         params = Map.new(Automator.cast(shortcut, params)),
         :ok <- Automator.run_shortcut(shortcut.automator, shortcut, params) do
      json(conn, "ok")
    else
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{"errors" => reason})
    end
  end
end
