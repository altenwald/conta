defmodule ContaWeb.EntryLive.FormComponent do
  use ContaWeb, :live_component
  import Conta.Commanded.Application, only: [dispatch: 1]
  require Logger

  alias Conta.Ledger
  alias ContaWeb.EntryLive.FormComponent.AccountTransaction, as: FormAccountTransaction

  @impl true
  def render(assigns) do
    ~H"""
    <div class="modal is-active">
      <div class="modal-background"></div>
      <div class="modal-card">
        <header class="modal-card-head">
          <h2><%= @title %></h2>
        </header>
        <section class="modal-card-body">
          <.simple_form
            for={@form}
            id="account-transaction-form"
            phx-target={@myself}
            phx-change="validate"
            phx-submit="save"
          >
            <.input field={@form[:ledger]} type="hidden" />
            <.input field={@form[:on_date]} type="date" label={gettext("Date")} />
            <.input field={@form[:breakdown]} type="checkbox" label={gettext("Breakdown")} />
            <%= if @breakdown do %>
              <div class="field is-horizontal">
                <div class="field-label is-normal">
                  <label class="label"><%= gettext("Entries") %></label>
                </div>
                <div class="field-body">
                  <.link class="button" phx-target={@myself} phx-click="add_entry">
                    <%= gettext("Add Entry") %>
                  </.link>
                </div>
              </div>
              <.inputs_for :let={d} field={@form[:entries]}>
                <div class="columns">
                  <div class="column is-one-fifth">
                    <.link
                      class="button is-danger"
                      phx-target={@myself}
                      phx-click="del_entry"
                      phx-value-index={d.index}
                    >
                      <%= gettext("Remove") %>
                    </.link>
                  </div>
                  <div class="column">
                    <.input
                      field={d[:description]}
                      label={gettext("Description")}
                      phx-mounted={if(d.index == 0, do: JS.focus())}
                    />
                    <.input
                      field={d[:account_name]}
                      label={gettext("Account")}
                      type="select"
                      options={list_accounts()}
                      prompt={gettext("Choose an account...")}
                    />
                    <.input field={d[:amount]} label={gettext("Amount")} type="number" step=".01" />
                  </div>
                </div>
              </.inputs_for>
            <% else %>
              <.input
                field={@form[:description]}
                label={gettext("Description")}
                type="text"
                phx-mounted={JS.focus()}
              />
              <.input
                field={@form[:account_name]}
                label={gettext("Account")}
                type="select"
                options={list_accounts()}
                prompt={gettext("Choose an account...")}
              />
              <.input
                field={@form[:related_account_name]}
                label={gettext("Related Account")}
                type="select"
                options={list_accounts()}
                prompt={gettext("Choose an account...")}
              />
              <.input field={@form[:amount]} label={gettext("Amount")} type="number" step=".01" />
            <% end %>
          </.simple_form>
        </section>
        <footer class="modal-card-foot is-at-right">
          <.button
            form="account-transaction-form"
            class="is-primary"
            phx-disable-with={gettext("Saving...")}
          >
            <%= gettext("Save Transaction") %>
          </.button>
          <.link class="button" patch={~p"/ledger/accounts/#{@account}/entries"}>
            <%= gettext("Cancel") %>
          </.link>
        </footer>
      </div>
    </div>
    """
  end

  defp list_accounts do
    for account <- Ledger.list_accounts(), do: Enum.join(account.name, ".")
  end

  @impl true
  def update(%{account_transaction: account_transaction} = assigns, socket) do
    params = %{
      "account_name" => Enum.join(assigns.account.name, ".")
    }

    Logger.debug("account transaction: #{inspect(account_transaction)}")
    changeset = FormAccountTransaction.changeset(account_transaction, params)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("del_entry", %{"index" => idx}, socket) do
    params = Map.update!(socket.assigns.params, "entries", &Map.delete(&1, idx))

    changeset = FormAccountTransaction.changeset(params)

    {:noreply,
     socket
     |> assign_form(changeset)
     |> assign(params: params)}
  end

  def handle_event("add_entry", _params, socket) do
    params =
      Map.update!(socket.assigns.params, "entries", fn entries ->
        [FormAccountTransaction.new() | Map.values(entries)]
        |> Enum.with_index(0)
        |> Map.new(fn {value, idx} -> {to_string(idx), value} end)
      end)

    changeset = FormAccountTransaction.changeset(params)

    {:noreply,
     socket
     |> assign_form(changeset)
     |> assign(params: params)}
  end

  def handle_event(
        "validate",
        %{"_target" => ["account_transaction", "breakdown"], "account_transaction" => params},
        socket
      ) do
    params =
      if socket.assigns.breakdown do
        FormAccountTransaction.disable_breakdown(params)
      else
        FormAccountTransaction.enable_breakdown(params)
      end

    changeset = FormAccountTransaction.changeset(params)

    {:noreply,
     socket
     |> assign_form(changeset)
     |> assign(
       params: params,
       breakdown: not socket.assigns.breakdown
     )}
  end

  def handle_event("validate", %{"account_transaction" => params} = global_params, socket) do
    changeset =
      socket.assigns.account_transaction
      |> FormAccountTransaction.changeset(params)
      |> Map.put(:action, :validate)

    if global_params["_target"] == ~w[account_transaction on_date] do
      send(self(), {:on_date, Ecto.Changeset.get_field(changeset, :on_date)})
    end

    {:noreply,
     socket
     |> assign_form(changeset)
     |> assign(params: params)}
  end

  def handle_event("save", %{"account_transaction" => params}, socket) do
    save_account_transaction(socket, socket.assigns.action, params)
  end

  defp save_account_transaction(socket, :duplicate, params) do
    save_account_transaction(socket, :new, params)
  end

  defp save_account_transaction(socket, :edit, params) do
    account_transaction = socket.assigns.account_transaction
    changeset = FormAccountTransaction.changeset(account_transaction, params)

    if changeset.valid? and dispatch(FormAccountTransaction.to_command(changeset)) == :ok do
      delete_transaction(account_transaction.transaction_id)

      {:noreply,
       socket
       |> put_flash(:info, gettext("Account transaction updated successfully"))
       |> push_patch(to: socket.assigns.patch)}
    else
      Logger.debug("changeset errors: #{inspect(changeset.errors)}")
      changeset = Map.put(changeset, :action, :validate)
      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_account_transaction(socket, :new, params) do
    changeset = FormAccountTransaction.changeset(socket.assigns.account_transaction, params)

    if changeset.valid? and dispatch(FormAccountTransaction.to_command(changeset)) == :ok do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Account transaction created successfully"))
       |> push_patch(to: socket.assigns.patch)}
    else
      Logger.debug("changeset errors: #{inspect(changeset.errors)}")
      changeset = Map.put(changeset, :action, :validate)
      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  def delete_transaction(transaction_id) do
    entries = Ledger.get_entries_by_transaction_id(transaction_id)

    command = %Conta.Command.RemoveAccountTransaction{
      ledger: "default",
      transaction_id: transaction_id,
      entries:
        for entry <- entries do
          %Conta.Command.RemoveAccountTransaction.Entry{
            account_name: entry.account_name,
            credit: entry.credit,
            debit: entry.debit
          }
        end
    }

    :ok = dispatch(command)
  end
end
