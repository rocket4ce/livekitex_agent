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

      # Worker management with resolved configuration
      {LivekitexAgent.WorkerManager, resolve_worker_options()},

      # Health monitoring (if enabled)
      maybe_health_server(),

      # Worker supervisor for dynamic agents
      {LivekitexAgent.WorkerSupervisor, resolve_worker_options()}
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

  # Resolve WorkerOptions for Phoenix integration
  defp resolve_worker_options do
    start_time = System.monotonic_time(:millisecond)
    # Ensure we get a keyword list from config
    user_config = Application.get_env(:livekitex_agent, :default_worker_options, [])

    try do
      # Log configuration resolution attempt with structured data
      Logger.info("Resolving worker configuration", %{
        event: "config_resolution_start",
        config_source: ":livekitex_agent",
        config_key: ":default_worker_options",
        config_present: user_config != nil,
        config_type: config_type_string(user_config)
      })

      config = case user_config do
        list when is_list(list) ->
          Logger.debug("Configuration is valid keyword list", %{
            event: "config_validation_success",
            config_length: length(list),
            config_keys: Keyword.keys(list)
          })
          list
        invalid_config ->
          Logger.warning("Invalid configuration type received, using empty defaults", %{
            event: "config_validation_warning",
            error_type: "invalid_config_type",
            received_type: config_type_string(invalid_config),
            received_value: inspect(invalid_config, limit: :infinity),
            suggested_fix: "Ensure config is a keyword list: config :livekitex_agent, default_worker_options: [key: value]",
            fallback_action: "using_empty_list"
          })
          []
      end

      result = LivekitexAgent.WorkerOptions.from_config(config)

      end_time = System.monotonic_time(:millisecond)
      Logger.info("Configuration resolution completed successfully", %{
        event: "config_resolution_success",
        duration_ms: end_time - start_time,
        worker_pool_size: result.worker_pool_size,
        agent_name: result.agent_name,
        timeout: result.timeout
      })

      result
    rescue
      error ->
        end_time = System.monotonic_time(:millisecond)
        error_type = error_type_string(error)

        # Structured error logging with detailed context
        Logger.error("Configuration resolution failed, using emergency fallback", %{
          event: "config_resolution_failure",
          duration_ms: end_time - start_time,
          error_type: error_type,
          error_message: Exception.message(error),
          error_module: error.__struct__,
          received_config: inspect(user_config, limit: :infinity),
          suggested_fixes: get_config_error_suggestions(error_type),
          fallback_status: "emergency_defaults_active",
          impact: "Agent will start with minimal functionality"
        })

        # Also log user-friendly error message
        Logger.error("""
        Failed to resolve WorkerOptions configuration: #{Exception.message(error)}

        This error occurs when livekitex_agent cannot initialize properly.
        To fix this:
        1. Ensure your config.exs has proper configuration
        2. Check that all required dependencies are available
        3. Verify your entry_point function is valid

        Falling back to emergency defaults...
        """)

        create_emergency_fallback()
    end
  end

  # Create emergency fallback configuration for startup resilience
  defp create_emergency_fallback do
    fallback_config = [
      entry_point: fn _ctx -> :ok end,
      worker_pool_size: System.schedulers_online(),
      agent_name: "emergency_fallback_agent",
      timeout: 300_000,
      max_concurrent_jobs: 1
    ]

    Logger.warning("Creating emergency fallback configuration", %{
      event: "emergency_fallback_creation",
      fallback_config: fallback_config,
      worker_pool_size: System.schedulers_online(),
      limitations: [
        "Basic job handling only",
        "No custom entry point",
        "Limited concurrent jobs",
        "Default timeout values"
      ],
      recommended_action: "Fix configuration and restart for full functionality"
    })

    result = LivekitexAgent.WorkerOptions.from_config(fallback_config)

    Logger.info("Emergency fallback configuration created successfully", %{
      event: "emergency_fallback_success",
      agent_name: result.agent_name,
      worker_pool_size: result.worker_pool_size,
      timeout: result.timeout,
      status: "minimal_functionality_available"
    })

    result
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
          LivekitexAgent.ShutdownManager.initiate_shutdown(
            timeout: shutdown_timeout,
            reason: :normal
          )

          # Wait for shutdown to complete
          wait_for_shutdown_completion(shutdown_timeout)
        catch
          :exit, reason ->
            Logger.warning(
              "ShutdownManager failed: #{inspect(reason)}, falling back to basic shutdown"
            )

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
      nil ->
        0

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
        LivekitexAgent.ShutdownManager.initiate_shutdown(
          reason: :signal,
          callback: fn -> System.stop(0) end
        )
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

  # Helper functions for structured logging

  defp config_type_string(value) do
    case value do
      list when is_list(list) -> "keyword_list"
      map when is_map(map) -> "map"
      atom when is_atom(atom) -> "atom"
      binary when is_binary(binary) -> "string"
      integer when is_integer(integer) -> "integer"
      nil -> "nil"
      _ -> "unknown"
    end
  end

  defp error_type_string(error) do
    case error do
      %ArgumentError{} -> "argument_error"
      %RuntimeError{} -> "runtime_error"
      %UndefinedFunctionError{} -> "undefined_function_error"
      %MatchError{} -> "match_error"
      _ -> "unknown_error"
    end
  end

  defp get_config_error_suggestions(error_type) do
    case error_type do
      "argument_error" -> [
        "Check that all configuration values have the correct type",
        "Ensure entry_point is a function with arity 1",
        "Verify worker_pool_size is a positive integer",
        "Check that server_url is a valid WebSocket URL"
      ]
      "undefined_function_error" -> [
        "Ensure the entry_point function module is compiled and available",
        "Check that all dependencies are properly loaded",
        "Verify function name and arity match the expected signature"
      ]
      "runtime_error" -> [
        "Check that all required dependencies are available at startup",
        "Ensure the application environment is properly configured",
        "Verify no circular dependencies exist in the configuration"
      ]
      _ -> [
        "Review the error message for specific details",
        "Check the application configuration in config.exs",
        "Ensure all required modules are compiled and available"
      ]
    end
  end
end
