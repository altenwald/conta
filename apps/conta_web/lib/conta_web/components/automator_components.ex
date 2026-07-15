defmodule ContaWeb.AutomatorComponents do
  @moduledoc """
  Shared components for the Filter/Shortcut Lua editor forms
  (`ContaWeb.FilterLive.Form` and `ContaWeb.ShortcutLive.Form`).
  """
  use Phoenix.Component
  use Gettext, backend: ContaWeb.Gettext

  @currencies Money.Currency.all() |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()

  @doc """
  Renders the Monaco-backed Lua code editor bound to a form field.

  The editor container has `phx-update="ignore"` so LiveView never
  touches its DOM after mount — all syncing back to the form happens
  through the hidden textarea via the `MonacoEditor` JS hook. It must be
  a `<textarea>`, not `type="text"`: single-line text inputs run the
  HTML value-sanitization algorithm, which silently strips newlines
  from `.value` every time the hook copies Monaco's content into it.
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :height, :string, default: "420px", doc: "minimum height; grows to fill a flex parent"

  def monaco_editor(assigns) do
    ~H"""
    <div class="fieldset mb-2 flex flex-col flex-1 min-h-0">
      <span class="label mb-1">{gettext("Code (Lua)")}</span>
      <div
        id={"#{@field.id}-editor"}
        phx-hook="MonacoEditor"
        phx-update="ignore"
        data-target={@field.id}
        data-value={@field.value}
        style={"flex: 1; min-height: #{@height}; border: 1px solid oklch(var(--bc)/0.2);"}
      >
      </div>
      <textarea
        class="hidden"
        id={@field.id}
        name={@field.name}
      >{Phoenix.HTML.Form.normalize_value("textarea", @field.value)}</textarea>
    </div>
    """
  end

  @doc """
  Renders the value of a param's `:options` field as comma-separated text.

  The changeset normalizes this field back into a list on every
  `phx-change`, so the raw list would otherwise reach the text input as-is
  and, since a list of binaries is valid iodata, render with no separator
  at all between entries.
  """
  def options_value(value) when is_list(value), do: Enum.join(value, ", ")
  def options_value(value), do: value

  @doc "The `Param.type` choices shared by the params-definition editor."
  def param_type_options do
    [
      {"string", "string"},
      {"date", "date"},
      {"integer", "integer"},
      {"money", "money"},
      {"currency", "currency"},
      {"options", "options"},
      {"account_name", "account_name"},
      {"table", "table"}
    ]
  end

  @doc """
  Renders one input control for a "test data" value, based on the
  `Param`'s `:type`. Used by the test-run panel in `FilterLive.Form`/
  `ShortcutLive.Form` — one of these per parameter defined on the
  filter/shortcut being edited.
  """
  attr :param, :any, required: true
  attr :value, :string, default: nil

  def test_param_input(assigns) do
    assigns = assign(assigns, :id, "test_params_#{assigns.param.name}")

    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span class="label mb-1">{@param.name}</span>
        {render_control(assigns)}
      </label>
    </div>
    """
  end

  defp render_control(%{param: %{type: :options}} = assigns) do
    ~H"""
    <select id={@id} name={"test_params[#{@param.name}]"} class="w-full select select-bordered">
      <option :for={opt <- @param.options || []} value={opt}>{opt}</option>
    </select>
    """
  end

  defp render_control(%{param: %{type: :currency}} = assigns) do
    assigns = assign(assigns, :currencies, @currencies)

    ~H"""
    <select id={@id} name={"test_params[#{@param.name}]"} class="w-full select select-bordered">
      <option :for={currency <- @currencies} value={currency}>{currency}</option>
    </select>
    """
  end

  defp render_control(%{param: %{type: :date}} = assigns) do
    ~H"""
    <input
      type="date"
      id={@id}
      name={"test_params[#{@param.name}]"}
      class="w-full input input-bordered"
    />
    """
  end

  defp render_control(%{param: %{type: type}} = assigns) when type in [:integer, :money] do
    ~H"""
    <input
      type="number"
      id={@id}
      name={"test_params[#{@param.name}]"}
      class="w-full input input-bordered"
    />
    """
  end

  defp render_control(%{param: %{type: :table}} = assigns) do
    ~H"""
    <textarea
      id={@id}
      name={"test_params[#{@param.name}]"}
      class="w-full textarea textarea-bordered"
      rows="3"
    ><%= @value %></textarea>
    """
  end

  defp render_control(assigns) do
    ~H"""
    <input
      type="text"
      id={@id}
      name={"test_params[#{@param.name}]"}
      class="w-full input input-bordered"
    />
    """
  end
end
