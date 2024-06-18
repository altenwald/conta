defmodule Conta.Projector.Automator do
  use Conta.Projector,
    application: Conta.Commanded.Application,
    repo: Conta.Repo,
    name: __MODULE__,
    consistency: Application.compile_env(:conta, :consistency, :eventual)

  require Logger

  alias Conta.Event.ShortcutRemoved
  alias Conta.Event.ShortcutSet
  alias Conta.Projector.Automator.Shortcut
  alias Conta.Repo

  project(%ShortcutSet{} = event, _metadata, fn multi ->
    event =
      event
      |> Map.from_struct()
      |> Map.update!(:params, fn params -> Enum.map(params, &Map.from_struct/1) end)

    if shortcut = Repo.get_by(Shortcut, name: event.name, automator: event.automator) do
      changeset = Shortcut.changeset(shortcut, event)
      Ecto.Multi.update(multi, :shortcut_update, changeset)
    else
      data = Shortcut.changeset(event)
      Ecto.Multi.insert(multi, :shortcut_create, data)
    end
  end)

  project(%ShortcutRemoved{} = event, _metadata, fn multi ->
    if shortcut = Repo.get_by(Shortcut, name: event.name, automator: event.automator) do
      Ecto.Multi.delete(multi, :delete, shortcut)
    else
      multi
    end
  end)
end
