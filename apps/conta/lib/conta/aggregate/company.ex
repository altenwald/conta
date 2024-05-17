defmodule Conta.Aggregate.Company do
  alias Conta.Aggregate.Company.Contact
  alias Conta.Aggregate.Company.PaymentMethod

  alias Conta.Command.SetInvoice
  alias Conta.Command.SetExpense
  alias Conta.Command.SetCompany
  alias Conta.Command.SetContact
  alias Conta.Command.SetPaymentMethod
  alias Conta.Command.SetTemplate

  alias Conta.Event.CompanySet
  alias Conta.Event.ContactSet
  alias Conta.Event.ExpenseSet
  alias Conta.Event.InvoiceSet
  alias Conta.Event.PaymentMethodSet
  alias Conta.Event.TemplateSet

  @type t() :: %__MODULE__{
    nif: nil | String.t(),
    name: nil | String.t(),
    postcode: nil | String.t(),
    city: nil | String.t(),
    state: nil | String.t(),
    country: nil | String.t(),
    details: nil | String.t(),
    invoice_numbers: %{pos_integer() => MapSet.t(pos_integer())},
    contacts: %{String.t() => Contact.t()},
    payment_methods: %{String.t() => PaymentMethod.t()},
    template_names: MapSet.t(String.t())
  }

  defstruct nif: nil,
            name: nil,
            address: nil,
            postcode: nil,
            city: nil,
            state: nil,
            country: nil,
            details: nil,
            invoice_numbers: %{},
            contacts: %{},
            payment_methods: %{},
            template_names: MapSet.new(["default"])

  def execute(_company, %SetCompany{} = command) do
    params = Map.from_struct(command)
    CompanySet.changeset(params)
  end

  def execute(%__MODULE__{nif: nil}, _command) do
    {:error, :company_not_found}
  end

  def execute(%__MODULE__{}, %SetTemplate{} = command) do
    params = Map.from_struct(command)
    TemplateSet.changeset(params)
  end

  def execute(%__MODULE__{}, %SetContact{} = command) do
    params = Map.from_struct(command)
    ContactSet.changeset(params)
  end

  def execute(%__MODULE__{}, %SetPaymentMethod{} = command) do
    params =
      command
      |> Map.from_struct()
      |> Map.update!(:method, &to_string/1)

    PaymentMethodSet.changeset(params)
  end

  def execute(_company, %SetInvoice{invoice_date: nil}) do
    {:error, %{invoice_date: ["can't be blank"]}}
  end

  def execute(_company, %SetExpense{invoice_date: nil}) do
    {:error, %{invoice_date: ["can't be blank"]}}
  end

  def execute(_company, %SetInvoice{invoice_number: nil, action: :update}) do
    {:error, %{invoice_number: ["can't be blank"]}}
  end

  def execute(_company, %SetExpense{invoice_number: nil, action: :update}) do
    {:error, %{invoice_number: ["can't be blank"]}}
  end

  def execute(%__MODULE__{} = company, %SetInvoice{invoice_number: nil} = command) do
    invoice_year = command.invoice_date.year
    invoice_numbers = company.invoice_numbers[invoice_year] || MapSet.new()
    last_invoice_number = Enum.max(invoice_numbers) || 0
    invoice_number = last_invoice_number + 1
    execute(company, %SetInvoice{command | invoice_number: invoice_number})
  end

  def execute(_company, %SetInvoice{client_nif: nil, destination_country: nil}) do
    {:error, %{destination_country: ["can't be blank if not provided client NIF"]}}
  end

  def execute(_company, %SetExpense{provider_nif: nil}) do
    {:error, %{provider_nif: ["can't be blank"]}}
  end

  def execute(_company, %SetInvoice{payment_method: nil}) do
    {:error, %{payment_method: ["can't be blank"]}}
  end

  def execute(_company, %SetExpense{payment_method: nil}) do
    {:error, %{payment_method: ["can't be blank"]}}
  end

  def execute(%__MODULE__{} = company, %SetInvoice{} = command) do
    invoice_year = command.invoice_date.year
    invoice_numbers = company.invoice_numbers[invoice_year] || MapSet.new()
    client_nif = command.client_nif
    payment_method = command.payment_method
    cond do
      MapSet.member?(invoice_numbers, command.invoice_number) and command.action == :insert ->
        {:error, %{invoice_number: ["can't be duplicated"]}}

      not MapSet.member?(invoice_numbers, command.invoice_number) and command.action == :update ->
        {:error, %{invoice_number: ["can't be found for update"]}}

      client_nif != nil and is_nil(company.contacts[client_nif]) ->
        {:error, %{client_nif: ["is invalid"]}}

      is_nil(company.payment_methods[payment_method]) ->
        {:error, %{payment_method: ["is invalid"]}}

      :else ->
        client = process_client(company.contacts[client_nif])
        country = if(client, do: client.country, else: command.destination_country)

        command
        |> Map.from_struct()
        |> Map.put(:client, client)
        |> Map.put(:destination_country, country)
        |> Map.put(:details, process_details(command))
        |> Map.put(:payment_method, process_payment_method(company.payment_methods[payment_method]))
        |> Map.put(:company, Map.take(company, ~w[nif name address postcode city state country details]a))
        |> InvoiceSet.changeset()
    end
  end

  def execute(%__MODULE__{} = company, %SetExpense{} = command) do
    provider_nif = command.provider_nif
    payment_method = command.payment_method
    cond do
      is_nil(company.contacts[provider_nif]) ->
        {:error, %{provider_nif: ["is invalid"]}}

      is_nil(company.payment_methods[payment_method]) ->
        {:error, %{payment_method: ["is invalid"]}}

      :else ->
        provider = Map.from_struct(company.contacts[provider_nif])

        command
        |> Map.from_struct()
        |> Map.put(:provider, provider)
        |> Map.put(:payment_method, process_payment_method(company.payment_methods[payment_method]))
        |> Map.put(:company, Map.take(company, ~w[nif name address postcode city state country details]a))
        |> ExpenseSet.changeset()
    end
  end

  defp process_client(nil), do: nil
  defp process_client(client), do: Map.from_struct(client)

  defp process_details(%_{details: []}), do: []
  defp process_details(%_{details: nil}), do: []
  defp process_details(%_{details: details}), do: Enum.map(details, &Map.from_struct/1)

  defp process_payment_method(nil), do: nil
  defp process_payment_method(payment) do
    payment
    |> Map.from_struct()
    |> Map.update!(:method, &to_string/1)
  end

  def apply(company, %CompanySet{} = event) do
    event
    |> Map.from_struct()
    |> then(&struct(company, &1))
  end

  def apply(%__MODULE__{} = company, %TemplateSet{} = event) do
    template_names = MapSet.put(company.template_names, event.name)
    %__MODULE__{company | template_names: template_names}
  end

  def apply(%__MODULE__{} = company, %InvoiceSet{action: :insert} = event) do
    year = to_date(event.invoice_date).year
    invoice_number = event.invoice_number
    invoice_numbers = Map.update(company.invoice_numbers, year, MapSet.new([invoice_number]), &MapSet.put(&1, invoice_number))
    %__MODULE__{company | invoice_numbers: invoice_numbers}
  end

  def apply(%__MODULE__{} = company, %InvoiceSet{action: :update}), do: company

  def apply(%__MODULE__{} = company, %ExpenseSet{}), do: company

  def apply(%__MODULE__{contacts: contacts} = company, %ContactSet{nif: nif} = event) do
    event
    |> Map.from_struct()
    |> then(&struct(Contact, &1))
    |> then(&%__MODULE__{company | contacts: Map.put(contacts, nif, &1)})
  end

  def apply(%__MODULE__{payment_methods: payment_methods} = company, %PaymentMethodSet{slug: slug} = event) do
    event
    |> Map.from_struct()
    |> then(&struct(PaymentMethod, &1))
    |> then(&%__MODULE__{company | payment_methods: Map.put(payment_methods, slug, &1)})
  end

  defp to_date(date) when is_struct(date, Date), do: date
  defp to_date(date) when is_binary(date), do: Date.from_iso8601!(date)
end
