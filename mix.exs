defmodule Conta.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      name: :conta,
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: releases(),
      preferred_cli_env: [
        release: :prod
      ]
    ]
  end

  defp deps do
    [
      {:observer_cli, "~> 1.6"},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.24", only: [:dev, :test], runtime: false},
      {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:mix_audit, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.14", only: [:dev, :test], runtime: false},
      # Required to run "mix format" on ~H/.heex files from the umbrella root
      {:phoenix_live_view, ">= 0.0.0"}
    ]
  end

  defp aliases do
    [
      setup: ["cmd mix setup"],
      release: [
        "local.hex --force",
        "local.rebar --force",
        "clean",
        "deps.get",
        "compile",
        "assets.setup",
        "assets.deploy",
        "phx.digest",
        "release"
      ]
    ]
  end

  defp releases do
    [
      conta: [
        steps: [
          :assemble,
          :tar
        ],
        applications: [
          conta: :permanent,
          conta_web: :permanent,
          conta_bot: :permanent
        ]
      ]
    ]
  end
end
