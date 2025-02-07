defmodule Conta.Aggregate.Automator do
  alias Conta.Command.RemoveFilter
  alias Conta.Command.RemoveShortcut
  alias Conta.Command.SetFilter
  alias Conta.Command.SetShortcut

  alias Conta.Event.FilterRemoved
  alias Conta.Event.FilterSet
  alias Conta.Event.ShortcutRemoved
  alias Conta.Event.ShortcutSet

  @derive Jason.Encoder

  @type t() :: %__MODULE__{
          shortcuts: MapSet.t(String.t()),
          filters: MapSet.t(String.t())
        }
  defstruct shortcuts: MapSet.new(),
            filters: MapSet.new()

  @doc false
  def changeset(params) do
    %__MODULE__{
      shortcuts: MapSet.new(params["shortcuts"]),
      filters: MapSet.new(params["filters"])
    }
  end

  def execute(_automator, %SetShortcut{} = command) do
    command
    |> Map.from_struct()
    |> Map.update!(:params, fn params ->
      Enum.map(params, &Map.from_struct/1)
    end)
    |> ShortcutSet.changeset()
  end

  def execute(_automator, %SetFilter{} = command) do
    command
    |> Map.from_struct()
    |> Map.update!(:params, fn params ->
      Enum.map(params, &Map.from_struct/1)
    end)
    |> FilterSet.changeset()
  end

  def execute(%__MODULE__{shortcuts: shortcuts}, %RemoveShortcut{} = command) do
    if MapSet.member?(shortcuts, command.name) do
      command
      |> Map.from_struct()
      |> ShortcutRemoved.changeset()
    else
      {:error, %{name: ["not found"]}}
    end
  end

  def execute(%__MODULE__{filters: filters}, %RemoveFilter{} = command) do
    if MapSet.member?(filters, command.name) do
      command
      |> Map.from_struct()
      |> FilterRemoved.changeset()
    else
      {:error, %{name: ["not found"]}}
    end
  end

  def apply(%__MODULE__{shortcuts: shortcuts} = automator, %ShortcutSet{name: name}) do
    %__MODULE__{automator | shortcuts: MapSet.put(shortcuts, name)}
  end

  def apply(%__MODULE__{shortcuts: shortcuts} = automator, %ShortcutRemoved{name: name}) do
    %__MODULE__{automator | shortcuts: MapSet.delete(shortcuts, name)}
  end

  def apply(%__MODULE__{filters: filters} = automator, %FilterSet{name: name}) do
    %__MODULE__{automator | filters: MapSet.put(filters, name)}
  end

  def apply(%__MODULE__{filters: filters} = automator, %FilterRemoved{name: name}) do
    %__MODULE__{automator | filters: MapSet.delete(filters, name)}
  end

  def apply(automator, _event), do: automator
end
