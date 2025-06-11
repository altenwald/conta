defmodule ContaWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as modals, tables, and
  forms. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.
  """
  use Phoenix.Component
  use Gettext, backend: ContaWeb.Gettext

  alias Phoenix.HTML.Form, as: HtmlForm
  alias Phoenix.LiveView.JS

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in your `assets/tailwind.config.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil
  attr :title, :string, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <% {name, type} = split_name_type(@name) %>
    <Heroicons.icon name={name} type={type} class={@class} title={@title} />
    """
  end

  defp split_name_type("hero-" <> name) do
    cond do
      String.ends_with?(name, "-outline") ->
        {String.replace_suffix(name, "-outline", ""), "outline"}

      String.ends_with?(name, "-solid") ->
        {String.replace_suffix(name, "-solid", ""), "solid"}

      String.ends_with?(name, "-mini") ->
        {String.replace_suffix(name, "-mini", ""), "mini"}

      String.ends_with?(name, "-micro") ->
        {String.replace_suffix(name, "-micro", ""), "micro"}

      :else ->
        {name, "outline"}
    end
  end

  @doc """
  Renders a header with title.
  """
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={@class}>
      <div>
        <h2><%= render_slot(@inner_block) %></h2>
        <p :if={@subtitle != []} class="mt-2">
          <%= render_slot(@subtitle) %>
        </p>
      </div>
      <div class="flex-none"><%= render_slot(@actions) %></div>
    </header>
    """
  end

  @doc """
  Renders the navigation elements.

  ## Examples

      <.nav/>
  """
  attr :logo_url, :string, required: true
  attr :class, :string, default: nil
  slot :navbar_start
  slot :navbar_end
  slot :inner_block, required: true

  def nav(assigns) do
    ~H"""
    <div class={["navbar bg-base-200", @class]}>
      <div class="navbar-start">
        <div class="dropdown">
          <div tabindex="0" role="button" class="btn btn-ghost lg:hidden">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-5 w-5"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h8m-8 6h16" />
            </svg>
          </div>
          <ul
            tabindex="0"
            class="menu menu-sm dropdown-content bg-base-100 rounded-box z-[1] mt-3 w-52 p-2 shadow"
          >
            {render_slot(@navbar_start)}
          </ul>
        </div>
        <a href={"/"} class="flex items-center">
          <img src={@logo_url} class="h-6 mr-3 sm:h-9 block" alt="Conta" />
        </a>
      </div>
      <div class="navbar-center hidden lg:flex">
        <ul class="menu menu-horizontal px-1">
          {render_slot(@navbar_start)}
        </ul>
      </div>
      <div class="navbar-end">
        <ul class="menu menu-horizontal px-1">
          {render_slot(@navbar_end)}
        </ul>
      </div>
    </div>
    """
  end

  attr :href, :string, default: "#"
  slot :inner_block, required: true

  def navbar_item(assigns) do
    ~H"""
    <li><a href={@href}>{render_slot(@inner_block)}</a></li>
    """
  end

  attr :name, :string, required: true
  slot :inner_block, required: true

  def navbar_dropdown(assigns) do
    ~H"""
    <li>
      <details>
        <summary>{@name}</summary>
        <ul class="p-2">
          {render_slot(@inner_block)}
        </ul>
      </details>
    </li>
    """
  end

  def navbar_divider(assigns) do
    ~H"""
    <div class="divider" />
    """
  end

  slot :breadcrumb do
    attr :href, :string
    attr :label, :string
  end

  def breadcrumbs(assigns) do
    breadcumbs = assigns.breadcrumb

    assigns =
      assign(assigns,
        first_breadcrumbs: Enum.drop(breadcumbs, -1),
        last_breadcrumb: List.last(breadcumbs)
      )

    ~H"""
    <nav class="breadcrumb" aria-label="breadcrumbs">
      <ul>
        <li :for={breadcrumb <- @first_breadcrumbs}>
          <a href={breadcrumb.href}><%= breadcrumb.label %></a>
        </li>
        <li class="is-active">
          <a aria-current="page" href={@last_breadcrumb.href}><%= @last_breadcrumb.label %></a>
        </li>
      </ul>
    </nav>
    """
  end

  slot :inner_block, required: true

  def buttons(assigns) do
    ~H"""
    <div class="buttons"><%= render_slot(@inner_block) %></div>
    """
  end

  @doc """
  Renders a button.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" class="ml-2">Send!</.button>
  """
  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(disabled form name value type)
  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button class={["button", @class]} {@rest}><%= render_slot(@inner_block) %></button>
    """
  end

  @doc """
  Renders a modal.

  ## Examples

      <.modal id="confirm-modal">
        This is a modal.
      </.modal>

  JS commands may be passed to the `:on_cancel` to configure
  the closing/cancel event, for example:

      <.modal id="confirm" on_cancel={JS.navigate(~p"/posts")}>
        This is another modal.
      </.modal>

  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="modal"
    >
      <div id={"#{@id}-bg"} class="modal-background" aria-hidden="true" />
      <div
        class="modal-content"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <.focus_wrap
          id={"#{@id}-container"}
          phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
          phx-key="escape"
          phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
        >
          <%= render_slot(@inner_block) %>
        </.focus_wrap>
      </div>
    </div>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      role="alert"
      class={[
        "fixed top-12 right-2 mr-2 w-80 sm:w-96 z-50 rounded-lg p-3 ring-1",
        @kind == :info && "bg-success text-stone-700 ring-success fill-success",
        @kind == :error && "bg-error text-stone-700 shadow-md ring-error fill-error"
      ]}
      {@rest}
    >
      <p :if={@title} class="flex items-center gap-1.5 text-sm font-semibold leading-6">
        <.icon :if={@kind == :info} name="hero-information-circle-mini" class="h-4 w-4" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle-mini" class="h-4 w-4" />
        {@title}
      </p>
      <p class="mt-2 text-sm leading-5">{msg}</p>
      <button type="button" class="group absolute top-1 right-1 p-2" aria-label={gettext("close")}>
        <.icon name="hero-x-mark-solid" class="h-5 w-5 opacity-40 group-hover:opacity-70" />
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} title={gettext("Success!")} flash={@flash} />
      <.flash kind={:error} title={gettext("Error!")} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={JS.remove_class("close", to: "#server-error")}
        phx-connected={JS.add_class("close", to: "#server-error")}
        hidden
      >
        {gettext("Hang in there while we get back on track")}
        <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr :for, :any, required: true, doc: "the datastructure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true

  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <%= render_slot(@inner_block, f) %>
      <div :for={action <- @actions}>
        <%= render_slot(action, f) %>
      </div>
    </.form>
    """
  end

  attr :for, :any, required: true, doc: "the datastructure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def modal_form(assigns) do
    ~H"""
    <div class="modal is-active">
      <div class="modal-background"></div>
      <div class="modal-card">
        <header class="modal-card-head">
          <p class="modal-card-title"><%= @title %></p>
        </header>
        <section class="modal-card-body">
          <.simple_form for={@for} as={@as} {@rest}>
            <%= render_slot(@inner_block) %>
          </.simple_form>
        </section>
        <footer class="modal-card-footer">
          <%= render_slot(@actions) %>
        </footer>
      </div>
    </div>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :class, :string, default: "is-horizontal"
  attr :label, :string, default: nil
  attr :control_label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
               range radio search select tel text textarea time url week static)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                pattern placeholder readonly required rows size step upload files)

  slot :inner_block

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        HtmlForm.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <.field id={@id} name={@name} label={@label} class={@class} errors={@errors}>
      <label class="b-checkbox checkbox mt-2">
        <input type="hidden" name={@name} value="false" />
        <input type="checkbox" id={@id} name={@name} value="true" checked={@checked} {@rest} />
        <span class="check"></span>
        <span class="control-label"><%= @control_label %></span>
      </label>
    </.field>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <.field id={@id} name={@name} label={@label} class={@class} errors={@errors}>
      <div class={[
        "select",
        "is-fullwidth",
        @multiple && "is-multiple",
        @errors != [] && "is-danger"
      ]}>
        <select id={@id} name={@name} multiple={@multiple} {@rest}>
          <option :if={@prompt} value=""><%= @prompt %></option>
          <%= Phoenix.HTML.Form.options_for_select(@options, @value) %>
        </select>
      </div>
    </.field>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <.field id={@id} name={@name} label={@label} class={@class} errors={@errors}>
      <textarea id={@id} name={@name} class={["textarea", @errors != [] && "is-danger"]} {@rest}><%= Phoenix.HTML.Form.normalize_value("textarea", @value) %></textarea>
    </.field>
    """
  end

  def input(%{type: "file"} = assigns) do
    ~H"""
    <.field id={@id} name={@name} label={@label} class={@class} errors={@errors}>
      <div class="box">
        <span :if={length(@rest.files) == 0 and length(@rest.upload.entries) == 0}>
          <%= gettext("There are no attachments") %>
        </span>
        <span :for={file <- @rest.files} class="tag is-success">
          <%= file["name"] %>
          <button
            type="button"
            class="delete is-small"
            phx-click="remove"
            phx-target={@rest."phx-target"}
            phx-value-id={file["id"]}
            data={[confirm: gettext("Are you sure?")]}
          />
        </span>
        <span :for={entry <- @rest.upload.entries} class="tag is-primary">
          <%= entry.client_name %>
          <button
            type="button"
            class="delete is-small"
            phx-click="remove"
            phx-target={@rest."phx-target"}
            phx-value-ref={entry.ref}
            data={[confirm: gettext("Are you sure?")]}
          />
        </span>
      </div>
      <div class="file is-primary">
        <label class="file-label">
          <.live_file_input upload={@rest.upload} class="file-input" />
          <span class="file-cta">
            <span class="file-icon">
              <.icon name="hero-arrow-up-tray" />
            </span>
            <span class="file-label"><%= gettext("Upload") %></span>
          </span>
        </label>
      </div>
    </.field>
    """
  end

  def input(%{type: "static"} = assigns) do
    ~H"""
    <.field label={@label} class={@class}>
      <input
        type="text"
        value={Phoenix.HTML.Form.normalize_value("text", @value)}
        class="input is-static"
        {@rest}
      />
    </.field>
    """
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" name={@name} value={Phoenix.HTML.Form.normalize_value("text", @value)} {@rest} />
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <.field id={@id} name={@name} label={@label} class={@class} errors={@errors}>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "input",
          @errors != [] && "is-danger"
        ]}
        {@rest}
      />
    </.field>
    """
  end

  attr :id, :string, default: ""
  attr :name, :string, default: ""
  attr :label, :string, default: ""
  attr :class, :string, default: ""
  attr :errors, :list, default: []
  slot :inner_block, required: true

  def field(assigns) do
    ~H"""
    <div class={["field", @class]}>
      <div :if={@label} class="field-label is-normal">
        <.label for={@id}><%= @label %></.label>
      </div>
      <div class="field-body">
        <div class="field">
          <div class="control" phx-feedback-for={@name}>
            <%= render_slot(@inner_block) %>
          </div>
          <.error :for={msg <- @errors}><%= msg %></.error>
        </div>
      </div>
    </div>
    """
  end

  attr :input_class, :string, default: ""
  attr :button_class, :string, default: "is-info"
  attr :label, :string
  attr :name, :string, default: "search"
  attr :value, :string
  attr :debounce, :integer, default: 1_000

  def search(assigns) do
    ~H"""
    <form role="search" phx-change="search">
      <div class="field has-addons">
        <div class="control">
          <input
            class={["input", @input_class]}
            type="search"
            placeholder={@label}
            name={@name}
            value={@value}
            phx-debounce={@debounce}
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
            enterkeyhint="search"
            spellcheck="false"
            phx-key="Enter"
          />
        </div>
      </div>
    </form>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="label">
      <%= render_slot(@inner_block) %>
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="help is-danger">
      <span class="icon-text">
        <.icon name="hero-exclamation-triangle" class="mr-3" />
        <%= render_slot(@inner_block) %>
      </span>
    </p>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= user.username %></:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :class, :string
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table is-fullwidth is-striped is-hoverable">
      <thead>
        <tr>
          <th :for={col <- @col}><%= col[:label] %></th>
          <th :if={@action != []}>
            <span class="sr-only"><%= gettext("Actions") %></span>
          </th>
        </tr>
      </thead>
      <tbody
        id={@id}
        phx-update={if is_struct(@rows, Phoenix.LiveView.LiveStream), do: "stream"}
        phx-viewport-bottom="next-page"
      >
        <tr :for={{id, %_{}} = row <- @rows} id={id}>
          <td :for={col <- @col} class={["is-vcentered", col[:class]]}>
            <%= render_slot(col, @row_item.(row)) %>
          </td>
          <td :if={@action != []} class="is-text-nowrap">
            <%= for action <- @action do %>
              <%= render_slot(action, @row_item.(row)) %>
            <% end %>
          </td>
        </tr>
        <tr :for={{id, %{title: title, row: row}} <- @rows} id={id}>
          <th :if={is_nil(row)} colspan={length(@col) + if(@action != [], do: 1, else: 0)}>
            <%= title %>
          </th>
          <td :for={col <- @col} :if={is_nil(title)} class={["is-vcentered", col[:class]]}>
            <%= render_slot(col, @row_item.({row.id, row})) %>
          </td>
          <td :if={@action != [] and is_nil(title)} class="is-text-nowrap">
            <%= for action <- @action do %>
              <%= render_slot(action, @row_item.({row.id, row})) %>
            <% end %>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc ~S"""
  Renders a very simple table with generic styling.

  ## Examples

      <.simple_table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= user.username %></:col>
      </.simple_table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true

  slot :col, required: true do
    attr :class, :string
    attr :label, :string
  end

  def simple_table(assigns) do
    ~H"""
    <table class="table is-fullwidth is-striped is-hoverable">
      <thead>
        <tr>
          <th :for={col <- @col}><%= col[:label] %></th>
        </tr>
      </thead>
      <tr :for={row <- @rows} id={row.id}>
        <td :for={col <- @col} class={["is-vcentered", col[:class]]}>
          <%= render_slot(col, row) %>
        </td>
      </tr>
    </table>
    """
  end

  @doc """
  Renders a back navigation link.

  ## Examples

      <.back navigate={~p"/posts"}>Back to posts</.back>
  """
  attr :navigate, :any, required: true
  slot :inner_block, required: true

  def back(assigns) do
    ~H"""
    <div class="mt-3">
      <.link navigate={@navigate} class="icon-text">
        <.icon name="hero-arrow-left" class="mr-2" />
        <span><%= render_slot(@inner_block) %></span>
      </.link>
    </div>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      transition: ""
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition: "is-hidden"
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(ContaWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(ContaWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
