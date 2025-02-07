defmodule Conta.Projector do
  @moduledoc """
  Read model projections for Commanded using Ecto.

  Note that this module is copied from
  https://github.com/commanded/commanded-ecto-projections

  The module was copied because makes no sense to have a dependency only
  for one module and because the project required to modify the module for
  make it more testable.
  """

  defmacro __using__(opts) do
    opts = opts || []

    quote location: :keep do
      @behaviour Conta.Projector

      @opts unquote(opts)
      @repo @opts[:repo] || Application.compile_env(:commanded_ecto_projections, :repo) ||
              raise("Commanded Ecto projections expects :repo to be configured in environment")
      @timeout @opts[:timeout] || :infinity

      # Pass through any other configuration to the event handler
      @handler_opts Keyword.drop(@opts, [:repo, :timeout, :consistency])

      unquote(__include_projection_version_schema__())

      use Ecto.Schema
      use Commanded.Event.Handler, @handler_opts

      import Ecto.Query
      import unquote(__MODULE__)

      def update_projection(event, metadata, multi_fn) do
        projection_name = Map.fetch!(metadata, :handler_name)
        event_number = Map.fetch!(metadata, :event_number)

        projection_version = %ProjectionVersion{
          projection_name: projection_name,
          last_seen_event_number: event_number
        }

        # Query to update an existing projection version with the last seen event number with
        # a check to ensure that the event has not already been projected.
        update_projection_version =
          from(pv in ProjectionVersion,
            where: pv.projection_name == ^projection_name and pv.last_seen_event_number < ^event_number,
            update: [set: [last_seen_event_number: ^event_number]]
          )

        multi =
          Ecto.Multi.new()
          |> Ecto.Multi.run(:track_projection_version, fn repo, _changes ->
            try do
              repo.insert(projection_version,
                on_conflict: update_projection_version,
                conflict_target: [:projection_name]
              )
            rescue
              exception in Ecto.StaleEntryError ->
                # Attempted to insert a projection version for an already seen event
                {:error, :already_seen_event}

              exception ->
                reraise exception, __STACKTRACE__
            end
          end)

        with %Ecto.Multi{} = multi <- multi_fn.(multi),
             {:ok, changes} <- transaction(multi) do
          if function_exported?(__MODULE__, :after_update, 3) do
            apply(__MODULE__, :after_update, [event, metadata, changes])
          else
            :ok
          end
        else
          {:error, :track_projection_version, :already_seen_event, _changes} -> :ok
          {:error, _stage, error, _changes} -> {:error, error}
          {:error, _error} = reply -> reply
        end
      end

      defp transaction(%Ecto.Multi{} = multi) do
        @repo.transaction(multi, timeout: @timeout, pool_timeout: @timeout)
      end
    end
  end

  ## User callbacks

  @optional_callbacks [after_update: 3]

  @doc """
  The optional `after_update/3` callback function defined in a projector is
  called after each projected event.

  The function receives the event, its metadata, and all changes from the
  `Ecto.Multi` struct that were executed within the database transaction.

  You could use this function to notify subscribers that the read model has been
  updated, such as by publishing changes via Phoenix PubSub channels.

  ## Example

      defmodule MyApp.ExampleProjector do
        use Conta.Projector,
          application: MyApp.Application,
          repo: MyApp.Projections.Repo,
          name: "MyApp.ExampleProjector"

        project %AnEvent{name: name}, fn multi ->
          Ecto.Multi.insert(multi, :example_projection, %ExampleProjection{name: name})
        end

        @impl Conta.Projector
        def after_update(event, metadata, changes) do
          # Use the event, metadata, or `Ecto.Multi` changes and return `:ok`
          :ok
        end
      end

  """
  @callback after_update(event :: struct, metadata :: map, changes :: Ecto.Multi.changes()) ::
              :ok | {:error, any}

  defp __include_projection_version_schema__ do
    quote do
      defmodule ProjectionVersion do
        @moduledoc false
        use Ecto.Schema

        @primary_key {:projection_name, :string, []}

        schema "projection_versions" do
          field(:last_seen_event_number, :integer)

          timestamps(type: :naive_datetime_usec)
        end
      end
    end
  end

  defmacro project(event, do: block) do
    IO.warn(
      "project macro with \"do end\" block is deprecated; use project/2 with function instead",
      Macro.Env.stacktrace(__ENV__)
    )

    quote do
      def handle(unquote(event) = event, metadata) do
        update_projection(event, metadata, fn var!(multi) ->
          unquote(block)
        end)
      end
    end
  end

  @doc """
  Project a domain event into a read model by appending one or more operations
  to the `Ecto.Multi` struct passed to the projection function you define

  The operations will be executed in a database transaction including an
  idempotency check to guarantee an event cannot be projected more than once.

  ## Example

      project %AnEvent{}, fn multi ->
        Ecto.Multi.insert(multi, :my_projection, %MyProjection{...})
      end

  """
  defmacro project(event, lambda) do
    quote do
      def handle(unquote(event) = event, metadata) do
        update_projection(event, metadata, unquote(lambda))
      end
    end
  end

  defmacro project(event, metadata, do: block) do
    IO.warn(
      "project macro with \"do end\" block is deprecated; use project/3 with function instead",
      Macro.Env.stacktrace(__ENV__)
    )

    quote do
      def handle(unquote(event) = event, unquote(metadata) = metadata) do
        update_projection(event, metadata, fn var!(multi) ->
          unquote(block)
        end)
      end
    end
  end

  @doc """
  Project a domain event and its metadata map into a read model by appending one
  or more operations to the `Ecto.Multi` struct passed to the projection
  function you define.

  The operations will be executed in a database transaction including an
  idempotency check to guarantee an event cannot be projected more than once.

  ## Example

      project %AnEvent{}, metadata, fn multi ->
        Ecto.Multi.insert(multi, :my_projection, %MyProjection{...})
      end

  """
  defmacro project(event, metadata, lambda) do
    quote do
      def handle(unquote(event) = event, unquote(metadata) = metadata) do
        update_projection(event, metadata, unquote(lambda))
      end
    end
  end
end
