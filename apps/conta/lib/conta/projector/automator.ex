defmodule Conta.Projector.Automator do
  use Conta.Projector,
    application: Conta.Commanded.Application,
    repo: Conta.Repo,
    name: __MODULE__,
    consistency: Application.compile_env(:conta, :consistency, :eventual)

  require Logger

  alias Conta.Event.FilterRemoved
  alias Conta.Event.FilterSet
  alias Conta.Event.ImporterRemoved
  alias Conta.Event.ImporterSet
  alias Conta.Event.ShortcutRemoved
  alias Conta.Event.ShortcutSet

  alias Conta.Projector.Automator.Filter
  alias Conta.Projector.Automator.Importer
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

  project(%FilterSet{} = event, _metadata, fn multi ->
    event =
      event
      |> Map.from_struct()
      |> Map.update!(:params, fn params -> Enum.map(params, &Map.from_struct/1) end)

    if filter = Repo.get_by(Filter, name: event.name, automator: event.automator) do
      changeset = Filter.changeset(filter, event)
      Ecto.Multi.update(multi, :filter_update, changeset)
    else
      data = Filter.changeset(event)
      Ecto.Multi.insert(multi, :filter_create, data)
    end
  end)

  project(%ShortcutRemoved{} = event, _metadata, fn multi ->
    if shortcut = Repo.get_by(Shortcut, name: event.name, automator: event.automator) do
      Ecto.Multi.delete(multi, :delete, shortcut)
    else
      multi
    end
  end)

  project(%FilterRemoved{} = event, _metadata, fn multi ->
    if filter = Repo.get_by(Filter, name: event.name, automator: event.automator) do
      Ecto.Multi.delete(multi, :delete, filter)
    else
      multi
    end
  end)

  project(%ImporterSet{} = event, _metadata, fn multi ->
    event = Map.from_struct(event)

    if importer = Repo.get_by(Importer, name: event.name, automator: event.automator) do
      changeset = Importer.changeset(importer, event)
      Ecto.Multi.update(multi, :importer_update, changeset)
    else
      data = Importer.changeset(event)
      Ecto.Multi.insert(multi, :importer_create, data)
    end
  end)

  project(%ImporterRemoved{} = event, _metadata, fn multi ->
    if importer = Repo.get_by(Importer, name: event.name, automator: event.automator) do
      Ecto.Multi.delete(multi, :delete, importer)
    else
      multi
    end
  end)
end
