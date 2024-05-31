defmodule ContaWeb.EntryLive.FormComponent.AccountTransaction do
  use TypedEctoSchema
  import Ecto.Changeset
  require Decimal
  alias Conta.Command.SetAccountTransaction

  @primary_key false

  typed_embedded_schema do
    field(:transaction_id, :binary_id)
    field(:ledger, :string, default: "default")
    field(:on_date, :date)
    field(:description, :string)
    field(:account_name, :string)
    field(:related_account_name, :string)
    field(:amount, :decimal)
    field(:breakdown, :boolean, default: false)

    embeds_many :entries, Entry, primary_key: false do
      @typep currency() :: atom()

      field(:id, :binary_id)
      field(:description, :string)
      field(:account_name, :string)
      field(:amount, :decimal, default: 0)
      field(:change_currency, Money.Ecto.Currency.Type, default: :EUR) :: currency()
      field(:change_amount, :decimal, default: Decimal.new(0))
      field(:change_price, :decimal, default: Decimal.new(1))
    end
  end

  def new do
    %{
      "description" => "",
      "account_name" => "",
      "amount" => ""
    }
  end

  def edit([%Conta.Projector.Ledger.Entry{} = main_entry | _] = entries) do
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
            amount: Money.subtract(entry.debit, entry.credit) |> Money.to_decimal()
            # TODO missing change information in projection (check Conta.Projector.Ledger.Entry)
          }
        end
    }
  end

  defp to_account_name(nil), do: nil

  defp to_account_name(account_name) when is_list(account_name) do
    Enum.join(account_name, ".")
  end

  def enable_breakdown(params) do
    Map.put(params, "entries", %{
      "0" => %{
        "description" => params["description"],
        "account_name" => params["account_name"],
        "amount" => params["amount"]
      },
      "1" => %{
        "description" => params["description"],
        "account_name" => params["related_account_name"],
        "amount" => negate_amount!(params["amount"])
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
      "amount" => entry1["amount"]
    }
  end

  defp negate_amount!(""), do: ""

  defp negate_amount!(money) when is_binary(money) do
    {number, ""} = Decimal.parse(money)

    number
    |> Decimal.negate()
    |> Decimal.to_string()
  end

  @required_fields ~w[on_date description account_name related_account_name amount]a
  @optional_fields ~w[breakdown ledger]a

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
  @optional_fields ~w[change_currency change_amount change_price]a

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
    if Money.negative?(money), do: money.amount, else: 0
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
            account_name: String.split(acctrans.account_name, "."),
            credit: from_money(amount, :negative),
            debit: from_money(amount, :positive),
            change_currency: acctrans.change_currency,
            change_credit: from_money(change_amount, :negative),
            change_debit: from_money(change_amount, :positive),
            change_price: acctrans.change_price
          }
        end
    }
  end

  defp to_command_simple(acctrans) do
    amount = Money.parse!(acctrans.amount)

    %SetAccountTransaction{
      ledger: acctrans.ledger,
      on_date: acctrans.on_date,
      entries: [
        %SetAccountTransaction.Entry{
          description: acctrans.description,
          account_name: String.split(acctrans.account_name, "."),
          credit: from_money(amount, :negative),
          debit: from_money(amount, :positive)
        },
        %SetAccountTransaction.Entry{
          description: acctrans.description,
          account_name: String.split(acctrans.related_account_name, "."),
          credit: from_money(amount, :positive),
          debit: from_money(amount, :negative)
        }
      ]
    }
  end
end
