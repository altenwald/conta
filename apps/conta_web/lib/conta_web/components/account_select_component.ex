defmodule ContaWeb.AccountSelectComponent do
  @moduledoc """
  A dynamic, searchable account selector component with on-demand dropdown rendering.

  Renders an input displaying the selected account. The dropdown with matching accounts
  is only rendered while the user interacts (focus or search) and is completely removed
  from the DOM upon selection or click-away, eliminating DOM bloat in large tables.
  """

  use ContaWeb, :live_component

  @max_results 15

  @impl true
  @impl true
  def update(assigns, socket) do
    field = assigns[:field]
    socket = init_field_assigns(socket, field, assigns)
    assigns_to_merge = if field, do: Map.drop(assigns, [:field]), else: assigns

    {:ok,
     socket
     |> assign(assigns_to_merge)
     |> assign_new(:item_id, fn -> nil end)
     |> assign_new(:value, fn -> nil end)
     |> assign_new(:placeholder, fn -> gettext("Select an account") end)
     |> assign_new(:label, fn -> nil end)
     |> assign_new(:notify_to, fn -> nil end)
     |> assign_new(:class, fn -> nil end)
     |> assign_new(:form_id, fn -> nil end)
     |> assign_new(:open, fn -> false end)
     |> assign_new(:query, fn -> nil end)
     |> assign_new(:matches, fn -> [] end)
     |> assign_new(:active_index, fn -> 0 end)
     |> assign_new(:ignore_focus, fn -> false end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class={["relative w-full", @label && "fieldset mb-2", @class]}
      phx-hook=".AccountSelect"
      phx-click-away="close"
      phx-target={@myself}
    >
      <label :if={@label} for={"#{@id}-input"} class="label mb-1">
        <span class="label-text font-semibold">{@label}</span>
      </label>

      <input :if={@name} type="hidden" name={@name} value={@value} />

      <%= if @form_id do %>
        <form
          id={@form_id}
          phx-change="form_change"
          phx-submit="form_submit"
          phx-target={@myself}
          onsubmit="return false;"
          class="relative w-full"
        >
          {render_input_and_dropdown(assigns)}
        </form>
      <% else %>
        <div class="relative w-full">
          {render_input_and_dropdown(assigns)}
        </div>
      <% end %>

      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  defp render_input_and_dropdown(assigns) do
    ~H"""
    <div class="relative flex items-center">
      <input
        type="text"
        id={"#{@id}-input"}
        name={if @form_id, do: "value", else: nil}
        value={if @open && !is_nil(@query), do: @query, else: @value}
        placeholder={@placeholder}
        autocomplete="off"
        data-open={to_string(@open)}
        phx-focus="open"
        phx-click="open"
        phx-keyup="search"
        phx-keydown="keydown"
        phx-target={@myself}
        class={[
          "input input-sm w-full pr-8 text-ellipsis font-mono text-xs",
          @errors != [] && "input-error"
        ]}
      />
      <button
        type="button"
        id={"#{@id}-toggle"}
        tabindex="-1"
        phx-click="toggle"
        phx-target={@myself}
        class="absolute right-2 flex items-center text-base-content/50 hover:text-base-content cursor-pointer p-0.5 rounded transition-colors"
        title={if @open, do: gettext("Close"), else: gettext("Open accounts")}
      >
        <.icon :if={!@open} name="hero-chevron-down" class="w-4 h-4" />
        <.icon :if={@open} name="hero-magnifying-glass" class="w-4 h-4" />
      </button>
    </div>

    <button
      :if={@open}
      type="button"
      id={"#{@id}-backdrop"}
      tabindex="-1"
      class="fixed inset-0 z-40 bg-transparent cursor-default w-full h-full border-none outline-none p-0 m-0"
      phx-click="close"
      phx-target={@myself}
      aria-hidden="true"
    ></button>

    <div
      :if={@open}
      id={"#{@id}-dropdown"}
      class="absolute left-0 right-0 top-full mt-1 z-50 max-h-60 overflow-y-auto rounded-md bg-base-100 p-1 shadow-lg ring-1 ring-base-content/10 border border-base-200"
    >
      <ul class="menu menu-xs p-0 gap-0.5" role="listbox">
        <li :if={@matches == []} class="px-3 py-2 text-xs text-base-content/60 italic">
          {gettext("No matching accounts")}
        </li>
        <li :for={{account, index} <- Enum.with_index(@matches)} id={"#{@id}-opt-#{index}"}>
          <button
            type="button"
            role="option"
            aria-selected={@value == account}
            aria-current={if index == @active_index, do: "true", else: "false"}
            class={[
              "w-full text-left px-2.5 py-1.5 rounded text-xs font-mono flex items-center justify-between",
              index == @active_index && "bg-base-200 font-semibold",
              @value == account && "active font-bold"
            ]}
            phx-click="select"
            phx-value-account={account}
            phx-target={@myself}
          >
            <span class="truncate">{account}</span>
            <.icon :if={@value == account} name="hero-check" class="w-3.5 h-3.5 shrink-0 text-primary" />
          </button>
        </li>
      </ul>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".AccountSelect">
      export default {
        mounted() {
          this.handleKeydown = (e) => {
            if (e.target.tagName === "INPUT" && (e.key === "Enter" || e.key === "Escape")) {
              if (e.key === "Enter") {
                e.preventDefault();
              }
              e.target.blur();
            }
          };
          this.el.addEventListener("keydown", this.handleKeydown);

          this.handleInput = (e) => {
            if (e.target.tagName === "INPUT" && !e.target.name) {
              e.stopPropagation();
            }
          };
          this.el.addEventListener("input", this.handleInput);

          this.handleEvent("account-selected", (data) => {
            const input = this.el.querySelector("input[type=text]");
            if (input && input.id === data.id) {
              input.blur();
            }
          });
        },
        updated() {
          const active = this.el.querySelector('[aria-current="true"]');
          if (active) {
            active.scrollIntoView({ block: "nearest" });
          }
          const input = this.el.querySelector("input[type=text]");
          if (input && input.dataset.open === "false" && document.activeElement === input) {
            input.blur();
          }
        },
        destroyed() {
          this.el.removeEventListener("keydown", this.handleKeydown);
          this.el.removeEventListener("input", this.handleInput);
        }
      }
    </script>
    """
  end

  @impl true
  def handle_event("toggle", _params, socket) do
    if socket.assigns.open do
      {:noreply, assign(socket, open: false, query: nil, matches: [], active_index: 0, ignore_focus: false)}
    else
      matches = filter_accounts(socket.assigns.accounts, "", @max_results)

      {:noreply,
       assign(socket, open: true, query: "", matches: matches, active_index: 0, ignore_focus: false)}
    end
  end

  def handle_event("open", _params, socket) do
    cond do
      socket.assigns.open ->
        {:noreply, socket}

      socket.assigns[:ignore_focus] ->
        {:noreply, assign(socket, ignore_focus: false)}

      true ->
        matches = filter_accounts(socket.assigns.accounts, "", @max_results)

        {:noreply,
         assign(socket, open: true, query: "", matches: matches, active_index: 0, ignore_focus: false)}
    end
  end

  def handle_event("search", %{"key" => key}, socket)
      when key in [
             "ArrowDown",
             "ArrowUp",
             "ArrowLeft",
             "ArrowRight",
             "Enter",
             "Escape",
             "Tab",
             "Shift",
             "Control",
             "Alt",
             "Meta"
           ] do
    {:noreply, socket}
  end

  def handle_event("search", params, socket) do
    query = params["query"] || params["value"] || ""
    matches = filter_accounts(socket.assigns.accounts, query, @max_results)

    {:noreply,
     assign(socket, open: true, query: query, matches: matches, active_index: 0, ignore_focus: false)}
  end

  def handle_event("form_change", %{"value" => value}, socket) do
    if value in socket.assigns.accounts do
      select_account(socket, value)
    else
      matches = filter_accounts(socket.assigns.accounts, value, @max_results)

      {:noreply,
       assign(socket, open: true, query: value, matches: matches, active_index: 0, ignore_focus: false)}
    end
  end

  def handle_event("form_submit", _params, socket) do
    if socket.assigns.open and socket.assigns.matches != [] do
      account = Enum.at(socket.assigns.matches, socket.assigns.active_index)
      select_account(socket, account)
    else
      {:noreply, socket}
    end
  end

  def handle_event("select", %{"account" => account}, socket) do
    select_account(socket, account)
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, open: false, query: nil, matches: [], active_index: 0, ignore_focus: false)}
  end

  def handle_event("keydown", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, open: false, query: nil, matches: [], active_index: 0, ignore_focus: false)}
  end

  def handle_event("keydown", %{"key" => "ArrowDown"}, socket) do
    if socket.assigns.open do
      max_idx = max(length(socket.assigns.matches) - 1, 0)
      next_idx = min(socket.assigns.active_index + 1, max_idx)
      {:noreply, assign(socket, active_index: next_idx)}
    else
      matches = filter_accounts(socket.assigns.accounts, socket.assigns.query || "", @max_results)

      {:noreply,
       assign(socket, open: true, query: "", matches: matches, active_index: 0, ignore_focus: false)}
    end
  end

  def handle_event("keydown", %{"key" => "ArrowUp"}, socket) do
    if socket.assigns.open do
      prev_idx = max(socket.assigns.active_index - 1, 0)
      {:noreply, assign(socket, active_index: prev_idx)}
    else
      matches = filter_accounts(socket.assigns.accounts, socket.assigns.query || "", @max_results)

      {:noreply,
       assign(socket, open: true, query: "", matches: matches, active_index: 0, ignore_focus: false)}
    end
  end

  def handle_event("keydown", %{"key" => "Enter"}, socket) do
    if socket.assigns.open and socket.assigns.matches != [] do
      account = Enum.at(socket.assigns.matches, socket.assigns.active_index)
      select_account(socket, account)
    else
      {:noreply, socket}
    end
  end

  def handle_event("keydown", _params, socket) do
    {:noreply, socket}
  end

  defp select_account(socket, account) do
    target_id = socket.assigns[:item_id] || socket.assigns.id
    target = socket.assigns[:notify_to] || socket.assigns[:target]

    cond do
      is_struct(target, Phoenix.LiveComponent.CID) ->
        send_update(target, account_selected: {target_id, account})

      is_tuple(target) ->
        {mod, id} = target
        send_update(mod, id: id, account_selected: {target_id, account})

      is_pid(target) ->
        send(target, {:account_selected, target_id, account})

      true ->
        send(self(), {:account_selected, target_id, account})
    end

    {:noreply,
     socket
     |> assign(
       open: false,
       query: nil,
       matches: [],
       value: account,
       active_index: 0,
       ignore_focus: true
     )
     |> push_event("account-selected", %{id: "#{socket.assigns.id}-input"})}
  end

  @doc """
  Filters a list of account names by substring matching with smart ranking.
  """
  def filter_accounts(accounts, query \\ nil, limit \\ @max_results)

  def filter_accounts(accounts, nil, limit) do
    Enum.take(accounts, limit)
  end

  def filter_accounts(accounts, query, limit) when is_binary(query) do
    trimmed = String.trim(query)

    if trimmed == "" do
      Enum.take(accounts, limit)
    else
      needle = String.downcase(trimmed)

      accounts
      |> Enum.filter(&String.contains?(String.downcase(&1), needle))
      |> Enum.sort_by(&account_rank(&1, needle))
      |> Enum.take(limit)
    end
  end

  defp account_rank(acc, needle) do
    lower = String.downcase(acc)

    cond do
      lower == needle -> {0, acc}
      String.starts_with?(lower, needle) -> {1, acc}
      String.contains?(lower, "." <> needle) -> {2, acc}
      true -> {3, acc}
    end
  end

  defp init_field_assigns(socket, nil, _assigns) do
    socket
    |> assign_new(:errors, fn -> [] end)
    |> assign_new(:name, fn -> nil end)
  end

  defp init_field_assigns(socket, %Phoenix.HTML.FormField{} = field, assigns) do
    errors =
      assigns[:errors] ||
        Enum.map(field.errors, &ContaWeb.CoreComponents.translate_error/1)

    socket
    |> assign_new(:id, fn -> field.id end)
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:item_id, fn -> to_string(field.field) end)
    |> assign(:errors, errors)
    |> assign_field_value(field, assigns)
  end

  defp assign_field_value(socket, _field, %{value: value}) do
    assign(socket, :value, value)
  end

  defp assign_field_value(socket, field, _assigns) do
    if socket.assigns[:open] do
      socket
    else
      assign(socket, :value, field.value)
    end
  end
end
