defmodule Livex.MixProject do
  use Mix.Project

  def project do
    [
      app: :livex,
      version: "0.2.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      description: description(),
      package: package(),
      docs: [
        main: "readme",
        extras: ["README.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix, "~> 1.7"},
      {:spark, "~> 2.0"},
      {:ecto, "~> 3.10"},
      {:jason, "~> 1.2"},
      # Test dependencies
      {:mimic, "~> 1.11", only: :test},
      {:floki, ">= 0.30.0", only: :test},
      {:esbuild, "~> 0.2", only: :dev},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Livex is a library that provides type-safe LiveView components and views with URL state management.
    """
  end

  defp package do
    [
      maintainers: ["Tom Clarke"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/u2i/livex"},
      files: ~w(lib assets/js package.json priv/static/ .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp aliases do
    [
      "assets.build": ["esbuild module", "esbuild cdn", "esbuild cdn_min", "esbuild main"],
      "assets.watch": ["esbuild module --watch"]
    ]
  end
end
