defmodule ContaWeb.AutomatorComponents do
  @moduledoc """
  Shared components for the Filter/Shortcut Lua editor forms
  (`ContaWeb.FilterLive.Form` and `ContaWeb.ShortcutLive.Form`).
  """
  use Phoenix.Component
  use Gettext, backend: ContaWeb.Gettext

  import ContaWeb.CoreComponents, only: [button: 1]

  @currencies Money.Currency.all() |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()

  @doc """
  Renders the Monaco-backed Lua code editor bound to a form field.

  The editor container has `phx-update="ignore"` so LiveView never
  touches its DOM after mount — all syncing back to the form happens
  through the hidden input via the `MonacoEditor` JS hook.
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :height, :string, default: "420px"

  def monaco_editor(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <span class="label mb-1">{gettext("Code (Lua)")}</span>
      <div
        id={"#{@field.id}-editor"}
        phx-hook="MonacoEditor"
        phx-update="ignore"
        data-target={@field.id}
        data-value={@field.value}
        style={"height: #{@height}; border: 1px solid oklch(var(--bc)/0.2);"}
      >
      </div>
      <input type="text" class="hidden" id={@field.id} name={@field.name} value={@field.value} />
    </div>
    """
  end

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
    <div class="flex gap-2 items-start">
      <textarea
        id={@id}
        name={"test_params[#{@param.name}]"}
        class="w-full textarea textarea-bordered"
        rows="3"
      ><%= @value %></textarea>
      <.button type="button" phx-click="load_table_sample" phx-value-param={@param.name} class="btn-sm">
        {gettext("Load real data")}
      </.button>
    </div>
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
