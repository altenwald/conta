defmodule Conta.Aggregate.Automator do
  alias Conta.Command.RemoveShortcut
  alias Conta.Command.SetShortcut
  alias Conta.Event.ShortcutRemoved
  alias Conta.Event.ShortcutSet

  @type t() :: %__MODULE__{
    shortcuts: MapSet.t(String.t())
  }
  defstruct shortcuts: MapSet.new()

  def execute(_automator, %SetShortcut{} = command) do
    command
    |> Map.from_struct()
    |> Map.update!(:params, fn params ->
      Enum.map(params, &Map.from_struct/1)
    end)
    |> ShortcutSet.changeset()
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

  def apply(%__MODULE__{shortcuts: shortcuts} = automator, %ShortcutSet{name: name}) do
    %__MODULE__{automator | shortcuts: MapSet.put(shortcuts, name)}
  end

  def apply(%__MODULE__{shortcuts: shortcuts} = automator, %ShortcutRemoved{name: name}) do
    %__MODULE__{automator | shortcuts: MapSet.delete(shortcuts, name)}
  end

  def apply(automator, _event), do: automator
end
