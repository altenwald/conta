defmodule ContaWeb.AccountLive.FormComponent do
  use ContaWeb, :live_component

  alias Conta.Ledger
  alias Conta.Command.SetAccount

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
            id="account-form"
            phx-target={@myself}
            phx-change="validate"
            phx-submit="save"
          >
            <.input
              field={@form[:ledger]}
              type="select"
              label={gettext("Ledger")}
              options={Ledger.list_ledgers()}
              prompt={gettext("Choose a ledger for the account...")}
            />
            <.input field={@form[:simple_name]} type="text" label={gettext("Name")} />
            <.input
              field={@form[:parent_name]}
              type="select"
              label={gettext("Parent")}
              options={for account <- Ledger.list_accounts(), do: Enum.join(account.name, ".")}
              prompt={gettext("(No parent)")}
            />
            <.input
              field={@form[:type]}
              type="select"
              label={gettext("Type")}
              options={[
                {gettext("Assets"), :assets},
                {gettext("Liabilities"), :liabilities},
                {gettext("Equity"), :equity},
                {gettext("Revenue"), :revenue},
                {gettext("Expenses"), :expenses},
              ]}
              prompt={gettext("Choose an account type...")}
            />
            <.input
              field={@form[:currency]}
              type="select"
              label={gettext("Currency")}
              options={
                Ledger.list_currencies()
                |> Enum.map(fn id -> {"#{Money.Currency.name(id)} (#{Money.Currency.symbol(id)})", id} end)
                |> Enum.sort()
              }
              prompt={gettext("Choose a currency...")}
            />
          </.simple_form>
        </section>
        <footer class="modal-card-foot is-at-right">
          <.button form="account-form" class="is-primary" phx-disable-with={gettext("Saving...")}>
            <%= gettext("Save Account") %>
          </.button>
          <.link class="button" patch={~p"/ledger/accounts"}>
            <%= gettext("Cancel") %>
          </.link>
        </footer>
      </div>
    </div>
    """
  end

  @impl true
  def update(%{account: account} = assigns, socket) do
    changeset = SetAccount.changeset(account, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"set_account" => account_params}, socket) do
    changeset =
      socket.assigns.account
      |> SetAccount.changeset(account_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"set_account" => account_params}, socket) do
    save_account(socket, socket.assigns.action, account_params)
  end

  defp save_account(socket, :edit, account_params) do
    case Ledger.update_account(socket.assigns.account, account_params) do
      {:ok, account} ->
        notify_parent({:saved, account})

        {:noreply,
         socket
         |> put_flash(:info, "Account updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_account(socket, :new, account_params) do
    case Ledger.create_account(account_params) do
      {:ok, account} ->
        notify_parent({:saved, account})

        {:noreply,
         socket
         |> put_flash(:info, "Account created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
