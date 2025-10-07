defmodule PhoenixTestApp.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PhoenixTestAppWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:phoenix_test_app, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PhoenixTestApp.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: PhoenixTestApp.Finch},
      # Start a worker by calling: PhoenixTestApp.Worker.start_link(arg)
      # {PhoenixTestApp.Worker, arg},
      # Start to serve requests, typically the last entry
      PhoenixTestAppWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PhoenixTestApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PhoenixTestAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
