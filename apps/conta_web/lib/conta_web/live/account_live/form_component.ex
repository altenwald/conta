defmodule ContaWeb.AccountLive.FormComponent do
  use ContaWeb, :live_component

  require Logger

  import Conta.Commanded.Application, only: [dispatch: 1]

  alias Conta.Command.SetAccount
  alias Conta.Ledger

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
          <.simple_form for={@form} id="account-form" phx-target={@myself} phx-change="validate" phx-submit="save">
            <.input field={@form[:ledger]} type="hidden" value="default" />
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
                {gettext("Expenses"), :expenses}
              ]}
              prompt={gettext("Choose an account type...")}
            />
            <.input
              field={@form[:currency]}
              type="select"
              label={gettext("Currency")}
              options={
                Ledger.list_currencies()
                |> Enum.map(fn id ->
                  {"#{Money.Currency.name(id)} (#{Money.Currency.symbol(id)})", id}
                end)
                |> Enum.sort()
              }
              prompt={gettext("Choose a currency...")}
            />
            <.input field={@form[:notes]} type="textarea" label={gettext("Notes")} />
          </.simple_form>
        </section>
        <footer class="modal-card-foot is-at-right">
          <.button form="account-form" class="is-primary" phx-disable-with={gettext("Saving...")}>
            <%= gettext("Save Account") %>
          </.button>
          <.link class="button" patch={@patch}>
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
    changeset = SetAccount.changeset(socket.assigns.account, account_params)

    if changeset.valid? and dispatch(SetAccount.to_command(changeset)) == :ok do
      message =
        case socket.assigns.action do
          :edit ->
            Logger.info("updated account #{inspect(account_params)}")
            gettext("Account updated successfully")

          :new ->
            Logger.info("created account #{inspect(account_params)}")
            gettext("Account created successfully")
        end

      {:noreply,
       socket
       |> put_flash(:info, message)
       |> push_patch(to: socket.assigns.patch)}
    else
      Logger.warning(
        "cannot #{socket.assigns.action} account #{inspect(Conta.EctoHelpers.get_result(changeset))}"
      )

      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
