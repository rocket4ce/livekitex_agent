# Test helper for LivekitexAgent

# Start ExUnit
ExUnit.start()

# Mox setup for mocking
Mox.defmock(MockWorkerManager, for: LivekitexAgent.WorkerManagerBehaviour)
Application.put_env(:livekitex_agent, :worker_manager, MockWorkerManager)

# Phoenix integration test support
defmodule PhoenixIntegrationSupport do
  @moduledoc """
  Support module for Phoenix integration testing.
  """

  def start_phoenix_test_app do
    # Clean up any existing applications
    stop_phoenix_test_app()

    # Start the Phoenix test application
    Application.load(:phoenix_test_app)

    # Configure Phoenix test app environment
    Application.put_env(:phoenix_test_app, PhoenixTestAppWeb.Endpoint,
      http: [ip: {127, 0, 0, 1}, port: 4002],
      server: false,
      secret_key_base: String.duplicate("test", 16)
    )

    case Application.start(:phoenix_test_app) do
      :ok -> :ok
      {:error, {:already_started, _}} -> :ok
      error -> error
    end
  end

  def stop_phoenix_test_app do
    Application.stop(:phoenix_test_app)
    Application.unload(:phoenix_test_app)
  end
end
