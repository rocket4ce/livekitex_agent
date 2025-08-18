defmodule LivekitexAgent.MixProject do
  use Mix.Project

  def project do
    [
      app: :livekitex_agent,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "LivekitexAgent",
      source_url: "https://github.com/rocket4ce/livekitex_agent",
      docs: [
        main: "LivekitexAgent",
        extras: ["README.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {LivekitexAgent.Application, []}
    ]
  end

  defp deps do
    [
      # JSON encoding/decoding
      {:jason, "~>  1.4.4"},

      # HTTP client (for LiveKit API and tool integrations)
      {:hackney, "~> 1.25.0"},
      {:httpoison, "~>  2.2.3"},

      # WebSocket client (for LiveKit connection)
      {:websockex, "~> 0.4.3"},

      # Time and date utilities
      {:timex, "~>  3.7.13"},

      # Configuration and environment
      {:ex_doc, "~>  0.38.3", only: :dev, runtime: false},
      {:credo, "~> 1.7.12", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.6", only: [:dev], runtime: false},

      # Testing
      {:mox, "~> 1.2.0", only: :test}
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
