defmodule Conta.MixProject do
  use Mix.Project

  def project do
    [
      app: :conta,
      version: "0.2.5",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      test_coverage: coverage(),
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Conta.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp coverage do
    [
      ignore_modules: [
        Conta.AccountsFixtures,
        Conta.AutomatorFixtures,
        Conta.BookFixtures,
        Conta.DirectoryFixtures,
        Conta.LedgerFixtures,
        Conta.Repo
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:bcrypt_elixir, "~> 3.0"},
      {:commanded, "~> 1.4"},
      {:jason, "~> 1.4"},
      {:commanded_eventstore_adapter, "~> 1.4"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, ">= 0.0.0"},
      {:typed_ecto_schema, "~> 0.4"},
      {:money, "~> 1.12"},
      {:dns_cluster, "~> 0.1"},
      {:phoenix_pubsub, "~> 2.1"},
      {:swoosh, "~> 1.14"},
      {:finch, "~> 0.17"},
      # https://github.com/mindok/contex/pull/93
      {:contex, "~> 0.5", github: "manuel-rubio/contex"},
      {:resvg, "~> 0.3"},
      {:luerl, "~> 1.1"},
      {:elixlsx, "~> 0.6"},
      {:countries, "~> 1.6"},
      {:ex_machina, "~> 2.7", only: :test},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      reset_es: ~w[event_store.drop event_store.create event_store.init],
      reset_db: ~w[ecto.drop ecto.create ecto.migrate],
      # test: ["reset_es", "reset_db", "test --cover"]
    ]
  end
end
