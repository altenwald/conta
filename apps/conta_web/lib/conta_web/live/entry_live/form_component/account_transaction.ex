defmodule ContaWeb.EntryLive.FormComponent.AccountTransaction do
  use TypedEctoSchema
  import Ecto.Changeset
  require Decimal
  alias Conta.Command.SetAccountTransaction

  @primary_key false

  @typep currency() :: atom()

  typed_embedded_schema do
    field(:transaction_id, :binary_id)
    field(:ledger, :string, default: "default")
    field(:on_date, :date)
    field(:description, :string)
    field(:account_name, :string)
    field(:related_account_name, :string)
    field(:amount, :decimal)
    field(:currency, Money.Ecto.Currency.Type, default: :EUR) :: currency()
    field(:change_amount, :decimal)
    field(:change_currency, Money.Ecto.Currency.Type, default: :EUR) :: currency()
    field(:breakdown, :boolean, default: false)

    embeds_many :entries, Entry, primary_key: false, on_replace: :delete do
      @typep currency() :: atom()

      field(:id, :binary_id)
      field(:description, :string)
      field(:account_name, :string)
      field(:currency, Money.Ecto.Currency.Type, default: :EUR) :: currency()
      field(:amount, :decimal, default: 0)
      field(:change_currency, Money.Ecto.Currency.Type, default: :EUR) :: currency()
      field(:change_amount, :decimal, default: Decimal.new(0))
    end
  end

  def new do
    %{
      "description" => "",
      "account_name" => "",
      "amount" => "",
      "change_amount" => ""
    }
  end

  def edit([%Conta.Projector.Ledger.Entry{} = main_entry | _] = entries) do
    currencies =
      case Enum.map(entries, & &1.change_currency) do
        [one] -> %{one => one}
        [first, second] -> %{first => second, second => first}
      end

    %__MODULE__{
      transaction_id: main_entry.transaction_id,
      on_date: main_entry.on_date,
      description: main_entry.description,
      account_name: to_account_name(main_entry.account_name),
      related_account_name: to_account_name(main_entry.related_account_name),
      amount: Money.subtract(main_entry.debit, main_entry.credit) |> Money.to_decimal(),
      breakdown: main_entry.breakdown,
      entries:
        for %Conta.Projector.Ledger.Entry{} = entry <- entries do
          %__MODULE__.Entry{
            id: entry.id,
            description: entry.description,
            account_name: to_account_name(entry.account_name),
            currency: currencies[entry.change_currency],
            amount: Money.subtract(entry.debit, entry.credit) |> Money.to_decimal()
          }
          |> maybe_change_data(entry)
        end
    }
    |> maybe_change_data(main_entry)
  end

  defp maybe_change_data(struct, entry)
       when entry.change_debit.amount != 0 or entry.change_credit.amount != 0 do
    Map.merge(struct, %{
      change_currency: entry.change_currency,
      change_amount: Money.subtract(entry.change_debit, entry.change_credit) |> Money.to_decimal()
    })
  end

  defp maybe_change_data(struct, _entry), do: struct

  defp to_account_name(nil), do: nil

  defp to_account_name(account_name) when is_list(account_name) do
    Enum.join(account_name, ".")
  end

  def enable_breakdown(params) do
    Map.put(params, "entries", %{
      "0" => %{
        "description" => params["description"],
        "account_name" => params["account_name"],
        "amount" => params["amount"],
        "currency" => params["currency"],
        "change_amount" => params["change_amount"],
        "change_currency" => params["change_currency"]
      },
      "1" => %{
        "description" => params["description"],
        "account_name" => params["related_account_name"],
        "amount" => negate_amount!(params["change_amount"]),
        "currency" => params["change_currency"],
        "change_amount" => negate_amount!(params["amount"]),
        "change_currency" => params["currency"]
      }
    })
  end

  def disable_breakdown(%{"entries" => entries} = params)
      when map_size(entries) >= 2 do
    [{_, entry1}, {_, entry2} | _] = Enum.to_list(entries)

    %{
      "breakdown" => "false",
      "on_date" => params["on_date"],
      "description" => entry1["description"],
      "account_name" => entry1["account_name"],
      "related_account_name" => entry2["account_name"],
      "amount" => entry1["amount"],
      "currency" => entry1["currency"],
      "change_amount" => entry1["change_amount"],
      "change_currency" => entry1["change_currency"]
    }
  end

  defp negate_amount!(""), do: ""

  defp negate_amount!(money) when is_binary(money) do
    {number, ""} = Decimal.parse(money)

    number
    |> Decimal.negate()
    |> Decimal.to_string()
  end

  @required_fields ~w[
    on_date
    description
    account_name
    related_account_name
    currency
    amount
  ]a
  @optional_fields ~w[
    breakdown
    ledger
    change_currency
    change_amount
  ]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> then(fn changeset ->
      if get_field(changeset, :breakdown) do
        changeset
        |> cast_embed(:entries, required: true, with: &changeset_entries/2)
        |> validate_required([:on_date])
      else
        validate_required(changeset, @required_fields)
      end
    end)
  end

  @required_fields ~w[description account_name amount]a
  @optional_fields ~w[change_currency change_amount]a

  @doc false
  def changeset_entries(model \\ %__MODULE__.Entry{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  def to_command(%Ecto.Changeset{valid?: true} = changeset) do
    acctrans = apply_changes(changeset)

    if get_field(changeset, :breakdown) do
      to_command_breakdown(acctrans)
    else
      to_command_simple(acctrans)
    end
  end

  defp from_money(money, :negative) do
    if Money.negative?(money), do: -money.amount, else: 0
  end

  defp from_money(money, :positive) do
    if Money.negative?(money), do: 0, else: money.amount
  end

  defp to_command_breakdown(acctrans) do
    %SetAccountTransaction{
      ledger: acctrans.ledger,
      on_date: acctrans.on_date,
      entries:
        for entry <- acctrans.entries do
          amount = Money.parse!(entry.amount)
          change_amount = Money.parse!(entry.change_amount)

          %SetAccountTransaction.Entry{
            description: entry.description,
            account_name: String.split(entry.account_name, "."),
            credit: from_money(amount, :negative),
            debit: from_money(amount, :positive),
            change_currency: entry.change_currency,
            change_credit: from_money(change_amount, :negative),
            change_debit: from_money(change_amount, :positive)
          }
        end
    }
  end

  defp to_command_simple(acctrans) do
    amount = Money.parse!(acctrans.amount)
    change_amount = Money.parse!(acctrans.change_amount || acctrans.amount)
    currency = acctrans.currency
    change_currency = acctrans.change_currency || currency

    %SetAccountTransaction{
      ledger: acctrans.ledger,
      on_date: acctrans.on_date,
      entries: [
        %SetAccountTransaction.Entry{
          description: acctrans.description,
          account_name: String.split(acctrans.account_name, "."),
          credit: from_money(amount, :negative),
          debit: from_money(amount, :positive),
          change_currency: change_currency,
          change_credit: from_money(change_amount, :negative),
          change_debit: from_money(change_amount, :positive)
        },
        %SetAccountTransaction.Entry{
          description: acctrans.description,
          account_name: String.split(acctrans.related_account_name, "."),
          credit: from_money(change_amount, :positive),
          debit: from_money(change_amount, :negative),
          change_currency: currency,
          change_credit: from_money(amount, :positive),
          change_debit: from_money(amount, :negative)
        }
      ]
    }
  end
end
