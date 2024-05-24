defmodule ContaBot.MixProject do
  use Mix.Project

  def project do
    [
      app: :conta_bot,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {ContaBot.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:ex_gram, "~> 0.50"},
      {:tesla, "~> 1.8"},
      {:finch, "~> 0.17"},
      {:jason, "~> 1.4"},
      {:gen_state_machine, "~> 3.0"},
      {:countries, "~> 1.6"},
      {:conta, in_umbrella: true},
      {:doctor, ">= 0.0.0", only: [:dev, :test], runtime: false}
    ]
  end
end
