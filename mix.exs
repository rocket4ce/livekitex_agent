defmodule LivekitexAgent.MixProject do
  use Mix.Project

  def project do
    [
      app: :livekitex_agent,
      version: "0.1.0",
      elixir: "~> 1.12",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "LivekitexAgent",
      source_url: "https://github.com/rocket4ce/livekitex_agent",

      # Testing
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],

      # Dialyzer
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix]
      ],

      # Documentation
      docs: [
        main: "LivekitexAgent",
        extras: ["README.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :ssl, :inets],
      mod: {LivekitexAgent.Application, []}
    ]
  end

  defp deps do
    [
      # LiveKit Elixir integration
      {:livekitex, "~> 0.1.34"},

      # WebSocket client (for LiveKit connection)
      {:websockex, "~> 0.4.3"},

      # HTTP client (for LiveKit API and tool integrations)
      {:httpoison, "~> 2.2.3"},
      {:hackney, "~> 1.25.0"},

      # JSON encoding/decoding
      {:jason, "~> 1.4.4"},

      # Time and date utilities
      {:timex, "~> 3.7.13"},

      # Development and testing
      {:ex_doc, "~> 0.38.3", only: :dev, runtime: false},
      {:credo, "~> 1.7.12", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.6", only: [:dev], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mox, "~> 1.2.0", only: :test},

      # Phoenix integration testing
      {:phoenix, "~> 1.8.1", only: :test},
      {:plug, "~> 1.15", only: :test}
    ]
  end

  defp description do
    """
    An Elixir library that replicates LiveKit Agents functionality for voice agents,
    including agent management, session handling, job contexts, worker management,
    function tools, and CLI utilities.
    """
  end

  defp package do
    [
      name: "livekitex_agent",
      files: ~w(lib .formatter.exs mix.exs README.md),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/rocket4ce/livekitex_agent"}
    ]
  end
end
