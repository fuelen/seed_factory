defmodule SeedFactory.MixProject do
  use Mix.Project
  @version "0.6.0"
  @source_url "https://github.com/fuelen/seed_factory"
  def project do
    [
      app: :seed_factory,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: Mix.env() != :dev,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      name: "SeedFactory",
      docs: [
        logo: "logo.svg",
        main: "SeedFactory",
        extras: ["CHANGELOG.md"],
        source_url: @source_url,
        source_ref: "v#{@version}"
      ],
      test_coverage: [
        tool: ExCoveralls
      ]
    ]
  end

  defp package do
    [
      description: "A toolkit for test data generation.",
      licenses: ["Apache-2.0"],
      links: %{
        GitHub: @source_url,
        Changelog: "https://hexdocs.pm/seed_factory/changelog.html"
      }
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
      {:spark, "~> 2.3"},
      {:libgraph, "~> 0.16"},
      {:excoveralls, "~> 0.10", only: :test},
      {:ex_doc, "~> 0.27", only: :dev, runtime: false}
    ]
  end
end
