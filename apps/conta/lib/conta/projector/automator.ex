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

  # Broadcasts so the *Index LiveViews can pick up rows created/edited from
  # their separate full-page Form LiveViews. `dispatch/1` in the Form only
  # waits for this projector's Ecto write with `:strong` consistency, which
  # this app doesn't request (default dispatch is `:eventual`) - so
  # `push_navigate`ing straight back to the index right after dispatch can
  # beat this handler to the read model. Broadcasting here, after the write
  # actually lands, lets the (already-subscribed) index catch up regardless
  # of that race, mirroring Conta.Projector.Book's after_update/3.
  @impl Conta.Projector
  def after_update(%ShortcutSet{}, _metadata, changes) do
    shortcut = changes[:shortcut_create] || changes[:shortcut_update]
    Phoenix.PubSub.broadcast(Conta.PubSub, "event:shortcut_set", {:shortcut_set, shortcut})
  end

  def after_update(%FilterSet{}, _metadata, changes) do
    filter = changes[:filter_create] || changes[:filter_update]
    Phoenix.PubSub.broadcast(Conta.PubSub, "event:filter_set", {:filter_set, filter})
  end

  def after_update(%ImporterSet{}, _metadata, changes) do
    importer = changes[:importer_create] || changes[:importer_update]
    Phoenix.PubSub.broadcast(Conta.PubSub, "event:importer_set", {:importer_set, importer})
  end

  def after_update(_event, _metadata, _changes), do: :ok
end
