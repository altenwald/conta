defmodule Conta.Projector.Rebuild do
  @moduledoc """
  Provides functions to rebuild Ecto read model projections from the EventStore.
  """

  import Ecto.Query

  alias Conta.Repo

  @projectors %{
    ledger: %{
      name: "ledger",
      module: Conta.Projector.Ledger,
      handler_name: "Conta.Projector.Ledger",
      schemas: [
        Conta.Projector.Ledger.Entry,
        Conta.Projector.Ledger.Balance,
        Conta.Projector.Ledger.Account
      ]
    },
    book: %{
      name: "book",
      module: Conta.Projector.Book,
      handler_name: "Conta.Projector.Book",
      schemas: [
        Conta.Projector.Book.Invoice,
        Conta.Projector.Book.Expense,
        Conta.Projector.Book.PaymentMethod,
        Conta.Projector.Book.Template
      ]
    },
    directory: %{
      name: "directory",
      module: Conta.Projector.Directory,
      handler_name: "Conta.Projector.Directory",
      schemas: [
        Conta.Projector.Directory.Contact
      ]
    },
    reconciliation: %{
      name: "reconciliation",
      module: Conta.Projector.Reconciliation,
      handler_name: "Conta.Projector.Reconciliation",
      schemas: [
        Conta.Projector.Reconciliation.Movement,
        Conta.Projector.Reconciliation.MatchRule
      ]
    },
    stats: %{
      name: "stats",
      module: Conta.Projector.Stats,
      handler_name: "Conta.Projector.Stats",
      schemas: [
        Conta.Projector.Stats.Account,
        Conta.Projector.Stats.Income,
        Conta.Projector.Stats.Outcome,
        Conta.Projector.Stats.Patrimony,
        Conta.Projector.Stats.ProfitsLoses
      ]
    },
    automator: %{
      name: "automator",
      module: Conta.Projector.Automator,
      handler_name: "Conta.Projector.Automator",
      schemas: [
        Conta.Projector.Automator.Filter,
        Conta.Projector.Automator.Importer,
        Conta.Projector.Automator.Shortcut
      ]
    }
  }

  @doc """
  Rebuilds one or all projections from EventStore.
  Accepts `:all`, `"all"`, or a specific projector atom/string/module:
  `:ledger`, `:book`, `:directory`, `:reconciliation`, `:stats`, `:automator`,
  or `Conta.Projector.Ledger`.
  """
  def rebuild(target \\ :all, opts \\ []) do
    projectors = resolve_projectors(target)

    for config <- projectors do
      rebuild_single(config, opts)
    end

    :ok
  end

  @doc """
  Returns a list of available projector identifiers.
  """
  def available_projectors, do: Map.keys(@projectors)

  defp resolve_projectors(target) when target in [:all, "all"] do
    Map.values(@projectors)
  end

  defp resolve_projectors(target) when is_atom(target) do
    find_by_key(target) || find_by_module(target) || unknown_projector!(target)
  end

  defp resolve_projectors(target) when is_binary(target) do
    find_by_binary_key(target) || unknown_projector!(target)
  end

  defp find_by_key(target) do
    case Map.get(@projectors, target) do
      nil -> nil
      config -> [config]
    end
  end

  defp find_by_module(target) do
    case Enum.find(@projectors, fn {_k, v} -> v.module == target end) do
      {_k, config} -> [config]
      nil -> nil
    end
  end

  defp find_by_binary_key(target) do
    with {:ok, atom} <- safe_to_atom(target),
         %{^atom => config} <- @projectors do
      [config]
    else
      _ -> nil
    end
  end

  defp safe_to_atom(string) do
    {:ok, String.to_existing_atom(String.downcase(string))}
  rescue
    ArgumentError -> :error
  end

  defp unknown_projector!(target) do
    raise ArgumentError, "Unknown projector: #{inspect(target)}"
  end

  defp rebuild_single(config, opts) do
    batch_size = Keyword.get(opts, :batch_size, 1_000)
    log? = Keyword.get(opts, :log, true)

    if log?, do: IO.puts("==> Rebuilding projection: #{config.name} (#{inspect(config.module)})...")

    # 1. Clear projection tables
    Enum.each(config.schemas, fn schema ->
      Repo.delete_all(schema)
    end)

    # 2. Reset projection version
    Repo.delete_all(
      from(pv in "projection_versions",
        where: pv.projection_name == ^config.handler_name or pv.projection_name == ^inspect(config.module)
      )
    )

    # 3. Stream and apply all events from EventStore
    total_replayed = replay_events(config, batch_size, log?)

    if log?, do: IO.puts("==> Successfully rebuilt #{config.name}: #{total_replayed} events replayed.\n")

    total_replayed
  end

  defp replay_events(config, batch_size, log?) do
    case Commanded.EventStore.stream_forward(Conta.Commanded.Application, "$all", 0, batch_size) do
      {:error, _} = error ->
        error

      enumerable ->
        Enum.reduce(enumerable, 0, &apply_event(&1, &2, config, log?))
    end
  end

  defp apply_event(ev, count, config, log?) do
    metadata = build_event_metadata(config, ev)
    dispatch_to_handler(config.module, ev.data, metadata)

    new_count = count + 1
    maybe_log_progress(new_count, log?)
    new_count
  end

  defp build_event_metadata(config, ev) do
    %{
      handler_name: config.handler_name,
      event_number: ev.event_number,
      event_id: ev.event_id,
      stream_id: ev.stream_id,
      stream_version: ev.stream_version,
      created_at: ev.created_at,
      causation_id: ev.causation_id,
      correlation_id: ev.correlation_id
    }
  end

  defp dispatch_to_handler(module, data, metadata) do
    module.handle(data, metadata)
  rescue
    FunctionClauseError -> :ok
  end

  defp maybe_log_progress(count, true) when rem(count, 2_000) == 0 do
    IO.puts("    ... #{count} events processed")
  end

  defp maybe_log_progress(_count, _log?), do: :ok
end
