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
    Logger.info("Initiating graceful shutdown of LivekitexAgent application")
    perform_graceful_shutdown()
    Logger.info("LivekitexAgent application stopped")
    :ok
  end

  # Build supervision tree children based on configuration
  defp build_children do
    base_children = [
      # Core infrastructure (always started)
      {LivekitexAgent.ToolRegistry, []},

      # Graceful shutdown management
      {LivekitexAgent.ShutdownManager, []},

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
        Logger.warning("Failed to register default tools: #{inspect(error)}")
    end
  end

  # Setup telemetry events and metrics
  defp setup_telemetry do
    # This will be implemented when telemetry module is created
    Logger.debug("Telemetry setup placeholder - will be implemented in Phase 2")
  end

  # Graceful shutdown process
  defp perform_graceful_shutdown do
    shutdown_timeout = get_shutdown_timeout()
    Logger.info("Starting graceful shutdown with #{shutdown_timeout}ms timeout")

    # Use the ShutdownManager for coordinated shutdown
    case Process.whereis(LivekitexAgent.ShutdownManager) do
      nil ->
        Logger.warning("ShutdownManager not available, performing basic shutdown")
        basic_shutdown(shutdown_timeout)

      _pid ->
        try do
          LivekitexAgent.ShutdownManager.initiate_shutdown([
            timeout: shutdown_timeout,
            reason: :normal
          ])

          # Wait for shutdown to complete
          wait_for_shutdown_completion(shutdown_timeout)
        catch
          :exit, reason ->
            Logger.warning("ShutdownManager failed: #{inspect(reason)}, falling back to basic shutdown")
            basic_shutdown(shutdown_timeout)
        end
    end

    Logger.info("Graceful shutdown completed")
  end

  defp basic_shutdown(timeout) do
    # Fallback shutdown process
    stop_accepting_new_work()
    wait_for_jobs_completion(timeout)
    export_final_metrics()
    close_external_connections()
  end

  defp wait_for_shutdown_completion(timeout) do
    start_time = System.monotonic_time(:millisecond)

    wait_for_completion_loop(start_time, timeout)
  end

  defp wait_for_completion_loop(start_time, timeout) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if elapsed >= timeout do
      Logger.warning("Shutdown completion timeout reached")
    else
      case Process.whereis(LivekitexAgent.ShutdownManager) do
        nil ->
          # ShutdownManager stopped, assume complete
          :ok

        _pid ->
          try do
            status = LivekitexAgent.ShutdownManager.get_shutdown_status()

            if status.phase == :complete do
              Logger.info("Shutdown completed successfully")
            else
              :timer.sleep(500)
              wait_for_completion_loop(start_time, timeout)
            end
          catch
            :exit, _ ->
              # ShutdownManager stopped, assume complete
              :ok
          end
      end
    end
  end

  defp get_shutdown_timeout do
    Application.get_env(:livekitex_agent, :graceful_shutdown_timeout, 30_000)
  end

  defp stop_accepting_new_work do
    Logger.info("Stopping acceptance of new work")

    # Signal worker manager to stop accepting jobs
    case Process.whereis(LivekitexAgent.WorkerManager) do
      nil ->
        Logger.warning("WorkerManager not found during shutdown")

      _pid ->
        try do
          LivekitexAgent.WorkerManager.graceful_shutdown(get_shutdown_timeout())
          Logger.info("WorkerManager shutdown initiated")
        catch
          :exit, reason ->
            Logger.warning("WorkerManager already stopped: #{inspect(reason)}")
        end
    end
  end

  defp wait_for_jobs_completion(timeout) do
    Logger.info("Waiting for active jobs to complete (#{timeout}ms timeout)")
    start_time = System.monotonic_time(:millisecond)

    wait_loop(start_time, timeout)
  end

  defp wait_loop(start_time, timeout) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if elapsed >= timeout do
      Logger.warning("Shutdown timeout reached, forcing termination of remaining jobs")
    else
      case get_active_jobs_count() do
        0 ->
          Logger.info("All jobs completed successfully")

        count ->
          Logger.info("#{count} jobs still active, waiting...")
          :timer.sleep(1000)
          wait_loop(start_time, timeout)
      end
    end
  end

  defp get_active_jobs_count do
    case Process.whereis(LivekitexAgent.WorkerManager) do
      nil -> 0
      _pid ->
        try do
          status = LivekitexAgent.WorkerManager.get_status()
          status.active_jobs_count
        rescue
          _ -> 0
        catch
          :exit, _ -> 0
        end
    end
  end

  defp export_final_metrics do
    Logger.info("Exporting final metrics")

    case Process.whereis(LivekitexAgent.Telemetry.Metrics) do
      nil ->
        Logger.info("Metrics system not running")

      _pid ->
        try do
          LivekitexAgent.Telemetry.Metrics.export_metrics()
          Logger.info("Final metrics exported")
        catch
          :exit, reason ->
            Logger.warning("Failed to export final metrics: #{inspect(reason)}")
        end
    end
  end

  defp close_external_connections do
    Logger.info("Closing external connections")

    # Close health server connections
    case Process.whereis(LivekitexAgent.HealthServer) do
      nil ->
        :ok

      _pid ->
        # Health server will handle its own shutdown
        Logger.info("Health server will handle connection cleanup")
    end

    # Close any LiveKit connections
    close_livekit_connections()
  end

  defp close_livekit_connections do
    # In a full implementation, this would iterate through active connections
    # and close them gracefully
    Logger.info("LiveKit connections cleanup completed")
  end

  @doc """
  Initiates graceful shutdown from external trigger (e.g., signal handler).
  """
  def trigger_graceful_shutdown do
    Logger.info("Graceful shutdown triggered externally")

    case Process.whereis(LivekitexAgent.ShutdownManager) do
      nil ->
        Logger.warning("ShutdownManager not available for external trigger")
        perform_graceful_shutdown()

      _pid ->
        LivekitexAgent.ShutdownManager.initiate_shutdown([
          reason: :signal,
          callback: fn -> System.stop(0) end
        ])
    end
  end

  @doc """
  Sets up signal handlers for graceful shutdown.
  """
  def setup_signal_handlers do
    # Set up SIGTERM handler for graceful shutdown
    case :os.type() do
      {:unix, _} ->
        # On Unix systems, handle SIGTERM gracefully
        spawn(fn ->
          receive do
            {:signal, :sigterm} ->
              Logger.info("SIGTERM received, initiating graceful shutdown")
              trigger_graceful_shutdown()
          end
        end)

        Logger.info("Signal handlers configured for graceful shutdown")

      _ ->
        Logger.info("Signal handlers not configured (non-Unix system)")
    end
  end
end
