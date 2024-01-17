defmodule Conta.Projector.Stats.Account do
  use Ecto.Schema
  import Ecto.Changeset

  @typedoc """
  The account types represent the typical financial accounts that exist:

  - `:assets`
    - Cash
    - Property
    - Equipment
    - Vehicle
    - Accounts Receivable
  - `:liabilities`
    - Bank Loans
    - Accounts Payable
    - Credit Cards
    - Unearned Revenues
    - Customer Credits
  - `:equity`
    - Owner's Equity
    - Owner's Draw
    - Owner's Contribution
    - Common Stocks
    - Retained Earnings
  - `:revenue`
    - Sales
    - Royalties
    - Cost of Goods Sold
  - `:expenses`
    - Wages
    - Rent
    - Phone Bills
    - Utilities

  In a personal context, you can use `:assets` for you money (cash and bank
  accounts), and everything that's an asset that helps you to make money.

  The `:liabilities` are your debts (i.e. loans and mortgage) or money you
  don't have but it's yours, like the rent deposit or any deposit indeed.

  The `:equity` for personal usage makes no sense.

  The `:revenue` could be used for putting here where we get the money. It
  could be referred to your payslips, author rights, etc.

  The `:expenses` are whatever you buy from shops like the supermarket or
  the expenses you have in your home (supplies or utilities), the rent or
  even taxes.
  """
  @type account_types() :: :assets | :liabilities | :equity | :revenue | :expenses

  @account_types ~w[assets liabilities equity revenue expenses]a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stats_accounts" do
    field(:name, {:array, :string})
    field(:ledger, :string, default: "default")
    field(:type, Ecto.Enum, values: @account_types)

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w[name]a
  @optional_fields ~w[ledger type]a

  @doc false
  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
