defmodule ContaWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :conta_web,
      version: "0.2.6",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {ContaWeb.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7.10"},
      {:phoenix_ecto, "~> 4.4"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:phoenix_live_reload, "~> 1.4", only: :dev},
      {:phoenix_live_view, "~> 0.20"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:dart_sass, "~> 0.1", runtime: Mix.env() == :dev},
      {:bulma, "~> 0.9"},
      {:fontawesome, "~> 0.3"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.24"},
      {:conta, in_umbrella: true},
      {:jason, "~> 1.4"},
      {:countries_i18n, "~> 0.0", only: :dev},
      {:countries, "~> 1.6"},
      {:plug_cowboy, "~> 2.6"},
      {:chromic_pdf, "~> 1.15"},
      {:doctor, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:sobelow, ">= 0.0.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": [
        # "tailwind.install --if-missing",
        "esbuild.install --if-missing"
      ],
      "assets.build": [
        # "tailwind default",
        "esbuild bundle_app",
        "esbuild bundle_print"
      ],
      "assets.deploy": [
        "sass default --no-source-map --style=compressed",
        # "tailwind default --minify",
        "esbuild bundle_app --minify",
        "esbuild bundle_print --minify",
        "phx.digest"
      ]
    ]
  end
end
