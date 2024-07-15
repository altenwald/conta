defmodule ContaWeb.EntryLive.FormComponent do
  use ContaWeb, :live_component

  import Conta.Commanded.Application, only: [dispatch: 1]
  import Ecto.Changeset, only: [get_field: 2]

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
          <div :if={@breakdown} class="is-right">
            <%= gettext("imbalance: %{currency_data}", currency_data: @currency_data) %>
          </div>
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
              <div class="notification">
                <.error :for={{error, _} <- @form[:entries].errors}>
                  <strong><%= gettext("Entries") %></strong>&nbsp;<%= error %>
                </.error>
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
                      options={list_accounts(@accounts)}
                      prompt={gettext("Choose an account...")}
                    />
                    <%= if @different_currency? do %>
                      <.input field={d[:currency]} type="hidden" />
                      <.input
                        field={d[:amount]}
                        label={gettext("Amount (%{currency})", currency: d[:currency].value)}
                        type="number"
                        step=".01"
                      />
                      <.input field={d[:change_currency]} type="hidden" />
                      <.input
                        field={d[:change_amount]}
                        label={gettext("Amount (%{currency})", currency: d[:change_currency].value)}
                        type="number"
                        step=".01"
                      />
                    <% else %>
                      <.input field={d[:currency]} type="hidden" />
                      <.input field={d[:amount]} label={gettext("Amount")} type="number" step=".01" />
                    <% end %>
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
                options={list_accounts(@accounts)}
                prompt={gettext("Choose an account...")}
              />
              <.input
                field={@form[:related_account_name]}
                label={gettext("Related Account")}
                type="select"
                options={list_accounts(@accounts)}
                prompt={gettext("Choose an account...")}
              />
              <%= if @different_currency? do %>
                <.input
                  field={@form[:amount]}
                  label={gettext("Amount (%{currency})", currency: @form[:currency].value)}
                  type="number"
                  step=".01"
                />
                <.input field={@form[:currency]} type="hidden" />
                <.input
                  field={@form[:change_amount]}
                  label={gettext("Amount (%{currency})", currency: @form[:change_currency].value)}
                  type="number"
                  step=".01"
                />
                <.input field={@form[:change_currency]} type="hidden" />
              <% else %>
                <.input field={@form[:amount]} label={gettext("Amount")} type="number" step=".01" />
                <.input field={@form[:change_amount]} type="hidden" value={@form[:amount].value} />
              <% end %>
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

  defp get_currencies(%{"entries" => entries, "breakdown" => "true"}) do
    Map.values(entries)
    |> Enum.flat_map(fn entry ->
      [
        %{currency: entry["currency"], amount: entry["amount"]},
        %{currency: entry["change_currency"], amount: entry["change_amount"]}
      ]
    end)
    |> Enum.reject(&is_nil(&1.currency))
    |> Enum.group_by(&to_string(&1.currency), & &1.amount)
    |> Enum.map_join("; ", fn {currency, amounts} ->
      "#{currency} = #{Enum.reduce(amounts, Decimal.new(0), &sum_decimal/2)}"
    end)
  end

  defp get_currencies(%{}), do: gettext("none")

  defp sum_decimal(number, acc) when is_binary(number) and is_struct(acc, Decimal) do
    case Decimal.parse(number) do
      {decimal, ""} -> Decimal.add(acc, decimal)
      _ -> acc
    end
  end

  defp sum_decimal(decimal, acc) when is_struct(decimal, Decimal) and is_struct(acc, Decimal) do
    Decimal.add(decimal, acc)
  end

  defp sum_decimal(nil, acc), do: acc

  defp assign_currencies(socket) do
    assign(socket, :currency_data, get_currencies(socket.assigns.form.params))
  end

  defp list_accounts(accounts) do
    Map.keys(accounts) |> Enum.sort()
  end

  defp list_accounts do
    Ledger.list_simple_accounts()
    |> Map.new(
      &{Enum.join(&1.name, "."),
       %{
         id: &1.id,
         currency: &1.currency,
         real_name: &1.name
       }}
    )
  end

  @impl true
  def update(assigns, socket) do
    %{account_transaction: %FormAccountTransaction{} = account_transaction} = assigns
    accounts = list_accounts()

    params =
      if account_transaction.breakdown do
        %{
          "breakdown" => "true",
          "entries" =>
            account_transaction.entries
            |> Enum.with_index()
            |> Map.new(fn {entry, idx} ->
              currency = get_currency(accounts, entry.account_name)

              {idx,
               %{
                 "description" => entry.description,
                 "account_name" => entry.account_name,
                 "currency" => currency,
                 "amount" => entry.amount,
                 "change_currency" => entry.change_currency,
                 "change_amount" => entry.change_amount
               }}
            end)
        }
      else
        account_name = account_transaction.account_name || Enum.join(assigns.account.name, ".")

        %{
          "account_name" => account_name,
          "related_account_name" => account_transaction.related_account_name,
          "currency" => get_currency(accounts, account_name),
          "amount" => account_transaction.amount,
          "change_currency" => get_currency(accounts, account_transaction.related_account_name),
          "change_amount" => account_transaction.change_amount
        }
      end

    Logger.debug("account transaction: #{inspect(account_transaction)}")
    changeset = FormAccountTransaction.changeset(account_transaction, params)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       accounts: accounts,
       different_currency?: different_currency?(accounts, changeset)
     )
     |> assign_form(changeset)
     |> assign_currencies()}
  end

  defp different_currency?(accounts, changeset) do
    if get_field(changeset, :breakdown) do
      changeset
      |> get_field(:entries)
      |> Enum.map(&accounts[&1.account_name])
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.currency)
      |> Enum.uniq()
      |> length() != 1
    else
      account = accounts[get_field(changeset, :account_name)]
      related_account = accounts[get_field(changeset, :related_account_name)]
      account != nil and related_account != nil and account.currency != related_account.currency
    end
  end

  @impl true
  def handle_event("del_entry", %{"index" => idx}, socket) do
    params = Map.update!(socket.assigns.params, "entries", &Map.delete(&1, idx))

    changeset = FormAccountTransaction.changeset(params)

    {:noreply,
     socket
     |> assign_form(changeset)
     |> assign_currencies()
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
     |> assign_currencies()
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
     |> assign_currencies()
     |> assign(
       params: params,
       breakdown: not socket.assigns.breakdown
     )}
  end

  def handle_event("validate", %{"account_transaction" => params} = global_params, socket) do
    accounts = socket.assigns.accounts

    params =
      if params["breakdown"] == "true" do
        params
        |> Map.put_new("entries", [])
        |> Map.update!("entries", &set_currency_for_entries(&1, accounts))
      else
        params
        |> Map.put("currency", get_currency(accounts, params["account_name"]))
        |> Map.put("change_currency", get_currency(accounts, params["related_account_name"]))
      end

    changeset =
      socket.assigns.account_transaction
      |> FormAccountTransaction.changeset(params)
      |> Map.put(:action, :validate)

    if global_params["_target"] == ~w[account_transaction on_date] do
      send(self(), {:on_date, get_field(changeset, :on_date)})
    end

    different_currency? = different_currency?(accounts, changeset)
    Logger.debug("different currency: #{different_currency?}")

    {:noreply,
     socket
     |> assign_form(changeset)
     |> assign_currencies()
     |> assign(params: params, different_currency?: different_currency?)}
  end

  def handle_event("save", %{"account_transaction" => params}, socket) do
    save_account_transaction(socket, socket.assigns.action, params)
  end

  defp get_currency(_accounts, nil), do: nil

  defp get_currency(accounts, account_name) do
    if(account = accounts[account_name], do: account.currency)
  end

  defp save_account_transaction(socket, :duplicate, params) do
    save_account_transaction(socket, :new, params)
  end

  defp save_account_transaction(socket, :edit, params) do
    account_transaction = socket.assigns.account_transaction
    changeset = FormAccountTransaction.changeset(account_transaction, params)

    if changeset.valid? and dispatch(FormAccountTransaction.to_command(changeset)) == :ok do
      :ok = Ledger.delete_account_transaction(account_transaction.transaction_id)

      {:noreply,
       socket
       |> put_flash(:info, gettext("Account transaction updated successfully"))
       |> push_patch(to: socket.assigns.patch)}
    else
      Logger.debug("changeset errors: #{inspect(changeset.errors)}")
      changeset = Map.put(changeset, :action, :validate)

      {:noreply,
       socket
       |> assign_form(changeset)
       |> assign_currencies()}
    end
  end

  defp save_account_transaction(socket, :new, params) do
    changeset = FormAccountTransaction.changeset(socket.assigns.account_transaction, params)

    with %Ecto.Changeset{valid?: true} <- changeset,
         :ok <- dispatch(FormAccountTransaction.to_command(changeset)) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Account transaction created successfully"))
       |> push_patch(to: socket.assigns.patch)}
    else
      {:error, errors} ->
        changeset =
          Enum.reduce(errors, changeset, fn {key, messages}, changeset ->
            Enum.reduce(messages, changeset, &Ecto.Changeset.add_error(&2, key, &1))
          end)
          |> Map.put(:action, :validate)

        Logger.warning("changeset errors: #{inspect(changeset.errors)}")

        {:noreply,
         socket
         |> assign_form(changeset)
         |> assign_currencies()}

      %Ecto.Changeset{} ->
        {:error, errors} = Conta.EctoHelpers.get_result(changeset)
        Logger.debug("changeset errors: #{inspect(errors)}")
        changeset = %Ecto.Changeset{changeset | action: :validate}

        {:noreply,
         socket
         |> assign_form(changeset)
         |> assign_currencies()}
    end
  end

  defp set_currency_for_entries(entries, accounts) do
    Map.new(entries, fn {idx, entry} ->
      currency = get_currency(accounts, entry["account_name"])
      {idx, Map.put(entry, "currency", currency)}
    end)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
