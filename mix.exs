defmodule Livex.MixProject do
  use Mix.Project

  def project do
    [
      app: :livex,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: description(),
      package: package()
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
      maintainers: ["Your Name"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/yourusername/livex"}
    ]
  end
end
