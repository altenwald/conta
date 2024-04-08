defmodule Conta.Aggregate.Company do
  alias Conta.Aggregate.Company.Contact
  alias Conta.Aggregate.Company.PaymentMethod

  alias Conta.Command.CreateInvoice
  alias Conta.Command.SetCompany
  alias Conta.Command.SetContact
  alias Conta.Command.SetPaymentMethod
  alias Conta.Command.SetTemplate

  alias Conta.Event.CompanySet
  alias Conta.Event.ContactSet
  alias Conta.Event.InvoiceCreated
  alias Conta.Event.PaymentMethodSet
  alias Conta.Event.TemplateSet

  defstruct nif: nil,
            name: nil,
            address: nil,
            postcode: nil,
            city: nil,
            state: nil,
            country: nil,
            invoice_numbers: %{},
            contacts: %{},
            payment_methods: %{},
            template_names: MapSet.new(["default"])

  def execute(_company, %SetCompany{} = command) do
    params = Map.from_struct(command)
    CompanySet.changeset(params)
  end

  def execute(%__MODULE__{nif: nil} = company, _command) do
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

  def execute(_company, %CreateInvoice{invoice_date: nil}) do
    {:error, :invalid_invoice_date}
  end

  def execute(%__MODULE__{} = company, %CreateInvoice{} = command) do
    invoice_year = command.invoice_date.year
    last_invoice_number = company.invoice_numbers[invoice_year] || 0
    invoice_number = command.invoice_number || last_invoice_number + 1
    client_nif = command.client_nif
    payment_method = command.payment_method
    cond do
      invoice_number <= last_invoice_number ->
        {:error, :too_low_invoice_number}

      client_nif != nil and is_nil(company.contacts[client_nif]) ->
        {:error, :invalid_client}

      is_nil(client_nif) and is_nil(command.destination_country) ->
        {:error, :country_not_found}

      is_nil(payment_method) or is_nil(company.payment_methods[payment_method]) ->
        {:error, :invalid_payment_method}

      :else ->
        command
        |> Map.from_struct()
        |> Map.put(:invoice_number, invoice_number)
        |> Map.put(:client, process_client(company.contacts[client_nif]))
        |> Map.put(:details, process_details(command))
        |> Map.put(:payment_method, process_payment_method(company.payment_methods[payment_method]))
        |> Map.put(:company, Map.take(company, ~w[nif name address postcode city state country]a))
        |> InvoiceCreated.changeset()
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

  def apply(%__MODULE__{} = company, %InvoiceCreated{} = event) do
    year = to_date(event.invoice_date).year
    invoice_number = event.invoice_number
    invoice_numbers = Map.put(company.invoice_numbers, year, invoice_number)
    %__MODULE__{company | invoice_numbers: invoice_numbers}
  end

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
