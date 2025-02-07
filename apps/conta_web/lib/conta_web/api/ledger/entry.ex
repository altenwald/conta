defmodule ContaWeb.Api.Ledger.Entry do
  use ContaWeb, :api

  require Logger

  import Conta.Commanded.Application, only: [dispatch: 1]
  import Conta.EctoHelpers

  alias Conta.Command.SetAccountTransaction
  alias Conta.Ledger

  @default_dates_per_page 5

  defp list_entries(account, params) do
    page = String.to_integer(params["page"] || "1")
    dates_per_page = params["dates_per_page"] || @default_dates_per_page

    case Ledger.list_entries_by_account(account, page, dates_per_page) do
      [] -> {:error, "no entries"}
      entries -> {:ok, entries, page, dates_per_page}
    end
  end

  defp get_account(account_name) do
    case Ledger.get_account_by_name(account_name) do
      {:ok, account} -> {:ok, account}
      {:error, _reason} -> {:error, "not found"}
    end
  end

  def index(conn, %{"account_name" => account_name} = params) do
    account_name = String.split(account_name, ".")

    with {:ok, account} <- get_account(account_name),
         {:ok, entries, page, dates_per_page} <- list_entries(account, params) do
      json(conn, %{
        "status" => "ok",
        "entries" =>
          for entry <- entries do
            %{
              "id" => entry.id,
              "on_date" => entry.on_date,
              "description" => entry.description,
              "credit" => Money.to_decimal(entry.credit),
              "debit" => Money.to_decimal(entry.debit),
              "balance" => Money.to_decimal(entry.balance),
              "related_account_name" => Enum.join(entry.related_account_name || ["-- Breakdown"], ".")
            }
          end,
        "page" => page,
        "currency" => account.currency,
        "dates_per_page" => dates_per_page
      })
    else
      {:error, reason} ->
        Logger.warning("transaction indexes failed: #{inspect(reason)}")

        conn
        |> put_status(:not_found)
        |> json(%{"status" => "error", "error" => reason})
    end
  end

  defp get_entry(id) do
    if entry = Ledger.get_entry(id) do
      {:ok, entry}
    else
      {:error, "entry not found"}
    end
  end

  def show(conn, %{"id" => id, "account_name" => account_name_str}) do
    account_name = String.split(account_name_str, ".")

    with {:ok, account} <- get_account(account_name),
         {:ok, entry} <- get_entry(id) do
      json(conn, %{
        "status" => "ok",
        "currency" => account.currency,
        "entry" => %{
          "id" => entry.id,
          "on_date" => entry.on_date,
          "description" => entry.description,
          "credit" => Money.to_decimal(entry.credit),
          "debit" => Money.to_decimal(entry.debit),
          "balance" => Money.to_decimal(entry.balance),
          "account_name" => account_name_str,
          "related_account_name" => Enum.join(entry.related_account_name || ["-- Breakdown"], "."),
          "breakdown" => entry.breakdown,
          "transaction_id" => entry.transaction_id,
          "updated_at" => entry.updated_at,
          "inserted_at" => entry.inserted_at
        }
      })
    else
      {:error, reason} ->
        Logger.warning("transaction indexes failed: #{inspect(reason)}")

        conn
        |> put_status(:not_found)
        |> json(%{"status" => "error", "error" => reason})
    end
  end

  defp to_account_name(account_name) when is_binary(account_name) do
    String.split(account_name, ".")
  end

  defp to_account_name(otherwise), do: otherwise

  def create(conn, params) do
    params =
      Map.update(params, "entries", [], fn entries ->
        for entry <- entries do
          Map.update(entry, "account_name", "", &to_account_name/1)
        end
      end)

    changeset = SetAccountTransaction.changeset(params)

    with %SetAccountTransaction{} = result <- get_result(changeset),
         :ok <- dispatch(result) do
      json(conn, %{"status" => "ok"})
    else
      {:error, reason} ->
        Logger.warning("cannot create #{inspect(changeset)}")

        conn
        |> put_status(:bad_request)
        |> json(%{"status" => "error", "errors" => reason})
    end
  end
end
