defmodule SeedFactory.MixProject do
  use Mix.Project
  @version "0.6.0"
  @source_url "https://github.com/fuelen/seed_factory"
  def project do
    [
      app: :seed_factory,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      name: "SeedFactory",
      docs: [
        logo: "logo.svg",
        main: "SeedFactory",
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
        GitHub: @source_url
      }
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:spark, "~> 2.1"},
      {:libgraph, "~> 0.16"},
      {:excoveralls, "~> 0.10", only: :test},
      {:ex_doc, "~> 0.27", only: :dev, runtime: false}
    ]
  end
end
