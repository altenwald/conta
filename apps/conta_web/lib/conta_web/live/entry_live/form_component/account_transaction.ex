defmodule ContaWeb.EntryLive.FormComponent.AccountTransaction do
  use TypedEctoSchema
  import Ecto.Changeset
  require Decimal
  alias Conta.Command.SetAccount
  alias Conta.Command.AccountTransaction, as: SetAccountTransaction

  @primary_key false

  typed_embedded_schema do
    field(:ledger, :string, default: "default")
    field(:on_date, :date)
    field(:description, :string)
    field(:account_name, :string)
    field(:related_account_name, :string)
    field(:amount, :decimal)
    field(:breakdown, :boolean, default: false)

    embeds_many :entries, Entry do
      @typep currency() :: atom()

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
  @optional_fields ~w[change_currency change_credit change_debit change_price]a

  @doc false
  def changeset_entries(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  def to_command(%Ecto.Changeset{valid?: true} = changeset) do
    acctrans = apply_changes(changeset)

    if get_field(changeset, :breakdown) do
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
              credit: if(Money.negative?(amount), do: amount.amount, else: 0),
              debit: if(Money.negative?(amount), do: 0, else: amount.amount),
              change_currency: acctrans.change_currency,
              change_credit:
                if(Money.negative?(change_amount), do: change_amount.amount, else: 0),
              change_debit: if(Money.negative?(change_amount), do: 0, else: change_amount.amount),
              change_price: acctrans.change_price
            }
          end
      }
    else
      amount = Money.parse!(acctrans.amount)

      %SetAccountTransaction{
        ledger: acctrans.ledger,
        on_date: acctrans.on_date,
        entries: [
          %SetAccountTransaction.Entry{
            description: acctrans.description,
            account_name: String.split(acctrans.account_name, "."),
            credit: if(Money.negative?(amount), do: amount.amount, else: 0),
            debit: if(Money.negative?(amount), do: 0, else: amount.amount)
          },
          %SetAccountTransaction.Entry{
            description: acctrans.description,
            account_name: String.split(acctrans.related_account_name, "."),
            credit: if(Money.negative?(amount), do: 0, else: amount.amount),
            debit: if(Money.negative?(amount), do: amount.amount, else: 0)
          }
        ]
      }
    end
  end
end
