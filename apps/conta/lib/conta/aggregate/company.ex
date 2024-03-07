defmodule Conta.Aggregate.Company do
  alias Conta.Command.CreateInvoice
  alias Conta.Command.SetCompany
  alias Conta.Command.SetContact
  alias Conta.Command.SetTemplate

  alias Conta.Event.CompanySet
  alias Conta.Event.ContactSet
  alias Conta.Event.InvoiceCreated
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
            template_names: MapSet.new(["default"])

  def execute(%__MODULE__{}, %SetCompany{} = command) do
    params = Map.from_struct(command)
    CompanySet.changeset(params)
  end

  def execute(%__MODULE__{}, %SetTemplate{} = command) do
    params = Map.from_struct(command)
    TemplateSet.changeset(params)
  end

  def execute(%__MODULE__{}, %SetContact{} = command) do
    params = Map.from_struct(command)
    ContactSet.changeset(params)
  end

  def execute(_company, %CreateInvoice{invoice_date: nil}) do
    {:error, :invalid_invoice_date}
  end

  def execute(%__MODULE__{} = company, %CreateInvoice{} = command) do
    invoice_year = command.invoice_date.year
    last_invoice_number = company.invoice_numbers[invoice_year] || 0
    invoice_number = command.invoice_number || last_invoice_number + 1
    client_name = command.client_name
    cond do
      invoice_number <= last_invoice_number ->
        {:error, :too_low_invoice_number}

      client_name != nil and is_nil(company.contacts[client_name]) ->
        {:error, :invalid_client}

      is_nil(client_name) and is_nil(command.destination_country) ->
        {:error, :country_not_found}

      :else ->
        command
        |> Map.from_struct()
        |> Map.put(:invoice_number, invoice_number)
        |> Map.put(:client, process_client(company.contacts[client_name]))
        |> Map.put(:details, process_details(command))
        |> Map.put(:payment_method, process_payment(command))
        |> Map.put(:company, Map.take(company, ~w[nif name address postcode city state country]a))
        |> InvoiceCreated.changeset()
    end
  end

  defp process_client(nil), do: %{}
  defp process_client(client), do: Map.from_struct(client)

  defp process_details(%_{details: []}), do: []
  defp process_details(%_{details: nil}), do: []
  defp process_details(%_{details: details}), do: Enum.map(details, &Map.from_struct/1)

  defp process_payment(%_{payment_method: nil}), do: %{}
  defp process_payment(%_{payment_method: payment}), do: Map.from_struct(payment)

  def apply(company, %CompanySet{} = event) do
    event
    |> Map.from_struct()
    |> then(&struct(company, &1))
  end

  def apply(%__MODULE__{nif: nil}, %TemplateSet{}) do
    {:error, :company_not_found}
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

  def apply(%__MODULE__{contacts: contacts} = company, %ContactSet{name: name} = event) do
    event
    |> Map.from_struct()
    |> then(&struct(Contact, &1))
    |> then(&%__MODULE__{company | contacts: Map.put(contacts, name, &1)})
  end

  defp to_date(date) when is_struct(date, Date), do: date
  defp to_date(date) when is_binary(date), do: Date.from_iso8601!(date)
end
