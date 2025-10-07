defmodule LivekitexAgent.Application do
  @moduledoc """
  The main application module for LivekitexAgent.

  This module starts the application supervision tree and initializes
  core components including:
  - Tool registry for global tool management
  - Worker manager for agent lifecycle
  - Health server for monitoring
  - Telemetry for metrics collection
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting LivekitexAgent application")

    children = build_children()
    opts = [strategy: :one_for_one, name: LivekitexAgent.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("LivekitexAgent application started successfully")
        post_start_setup()
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start LivekitexAgent application: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def stop(_state) do
    Logger.info("LivekitexAgent application stopped")
    :ok
  end

  # Build supervision tree children based on configuration
  defp build_children do
    base_children = [
      # Core infrastructure (always started)
      {LivekitexAgent.ToolRegistry, []},

      # Worker management
      {LivekitexAgent.WorkerManager, []},

      # Health monitoring (if enabled)
      maybe_health_server(),

      # Worker supervisor for dynamic agents
      {LivekitexAgent.WorkerSupervisor, []}
    ]

    # Filter out nil values (from disabled services)
    Enum.filter(base_children, & &1)
  end

  # Conditionally start health server based on configuration
  defp maybe_health_server do
    case Application.get_env(:livekitex_agent, :health_server, true) do
      true ->
        port = get_health_port()
        {LivekitexAgent.HealthServer, [port: port]}

      false ->
        nil
    end
  end

  # Get health check port from configuration
  defp get_health_port do
    Application.get_env(:livekitex_agent, :default_worker_options, [])
    |> Keyword.get(:health_check_port, 8080)
  end

  # Post-startup initialization
  defp post_start_setup do
    register_default_tools()
    setup_telemetry()
    Logger.info("LivekitexAgent post-startup setup completed")
  end

  # Register default tools from ExampleTools
  defp register_default_tools do
    try do
      tools = LivekitexAgent.ExampleTools.get_tools()

      Enum.each(tools, fn {_name, tool_def} ->
        LivekitexAgent.ToolRegistry.register(tool_def)
      end)

      Logger.info("Default tools registered: #{map_size(tools)} tools")
    rescue
      error ->
        Logger.warn("Failed to register default tools: #{inspect(error)}")
    end
  end

  # Setup telemetry events and metrics
  defp setup_telemetry do
    # This will be implemented when telemetry module is created
    Logger.debug("Telemetry setup placeholder - will be implemented in Phase 2")
  end
end
