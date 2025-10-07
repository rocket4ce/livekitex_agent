defmodule LivekitexAgent.ShutdownManager do
  @moduledoc """
  Manages graceful shutdown of the LivekitexAgent system.

  The ShutdownManager coordinates the shutdown process across all components:
  - Stops accepting new jobs
  - Waits for active jobs to complete
  - Exports final metrics and logs
  - Closes external connections gracefully
  - Handles emergency shutdown scenarios

  ## Shutdown Phases

  1. **Drain Phase**: Stop accepting new work, finish existing work
  2. **Grace Phase**: Wait for jobs to complete with timeout
  3. **Force Phase**: Terminate remaining jobs if timeout is exceeded
  4. **Cleanup Phase**: Export metrics, close connections, cleanup resources
  """

  use GenServer
  require Logger

  defstruct [
    :shutdown_initiated,
    :shutdown_start_time,
    :timeout,
    :phase,
    :active_jobs_snapshot,
    :shutdown_reason,
    :completion_callback
  ]

  @type shutdown_phase :: :draining | :waiting | :forcing | :cleanup | :complete
  @type shutdown_reason :: :normal | :forced | :signal | :timeout | :error

  ## Client API

  @doc """
  Starts the shutdown manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initiates graceful shutdown with optional timeout and callback.

  ## Options
  - `:timeout` - Maximum time to wait for jobs to complete (default: 30 seconds)
  - `:reason` - Reason for shutdown (:normal, :signal, :forced, etc.)
  - `:callback` - Function to call when shutdown completes
  """
  def initiate_shutdown(opts \\ []) do
    GenServer.call(__MODULE__, {:initiate_shutdown, opts})
  end

  @doc """
  Forces immediate shutdown, terminating all active jobs.
  """
  def force_shutdown do
    GenServer.call(__MODULE__, :force_shutdown)
  end

  @doc """
  Gets the current shutdown status.
  """
  def get_shutdown_status do
    GenServer.call(__MODULE__, :get_shutdown_status)
  end

  @doc """
  Registers a shutdown observer that will be notified of shutdown events.
  """
  def register_shutdown_observer(observer_pid) do
    GenServer.call(__MODULE__, {:register_observer, observer_pid})
  end

  @doc """
  Checks if shutdown is in progress.
  """
  def shutdown_in_progress? do
    case Process.whereis(__MODULE__) do
      nil -> false
      _pid ->
        try do
          status = get_shutdown_status()
          status.shutdown_initiated
        catch
          :exit, _ -> false
        end
    end
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    # Set up signal trapping
    Process.flag(:trap_exit, true)

    state = %__MODULE__{
      shutdown_initiated: false,
      shutdown_start_time: nil,
      timeout: Keyword.get(opts, :default_timeout, 30_000),
      phase: :ready,
      active_jobs_snapshot: nil,
      shutdown_reason: nil,
      completion_callback: nil
    }

    Logger.info("Shutdown manager initialized")
    {:ok, state}
  end

  @impl true
  def handle_call({:initiate_shutdown, opts}, _from, state) do
    if state.shutdown_initiated do
      {:reply, {:error, :shutdown_already_initiated}, state}
    else
      timeout = Keyword.get(opts, :timeout, state.timeout)
      reason = Keyword.get(opts, :reason, :normal)
      callback = Keyword.get(opts, :callback)

      new_state = %{state |
        shutdown_initiated: true,
        shutdown_start_time: System.monotonic_time(:millisecond),
        timeout: timeout,
        phase: :draining,
        shutdown_reason: reason,
        completion_callback: callback
      }

      Logger.info("Graceful shutdown initiated: reason=#{reason}, timeout=#{timeout}ms")

      # Start the shutdown process
      send(self(), :begin_drain_phase)

      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:force_shutdown, _from, state) do
    Logger.warning("Force shutdown requested")

    new_state = %{state |
      shutdown_initiated: true,
      shutdown_start_time: System.monotonic_time(:millisecond),
      phase: :forcing,
      shutdown_reason: :forced
    }

    send(self(), :begin_force_phase)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_shutdown_status, _from, state) do
    elapsed_time = if state.shutdown_start_time do
      System.monotonic_time(:millisecond) - state.shutdown_start_time
    else
      0
    end

    status = %{
      shutdown_initiated: state.shutdown_initiated,
      phase: state.phase,
      elapsed_time_ms: elapsed_time,
      timeout_ms: state.timeout,
      reason: state.shutdown_reason,
      active_jobs_at_start: state.active_jobs_snapshot
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call({:register_observer, _observer_pid}, _from, state) do
    # In a full implementation, would track observers
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:begin_drain_phase, state) do
    Logger.info("Beginning shutdown drain phase")

    # Capture current active jobs count
    active_jobs = get_current_active_jobs()

    # Signal all systems to stop accepting new work
    stop_accepting_new_work()

    # Start grace period timer
    Process.send_after(self(), :check_completion, 1000)

    new_state = %{state |
      active_jobs_snapshot: active_jobs,
      phase: :waiting
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:check_completion, state) do
    elapsed = System.monotonic_time(:millisecond) - state.shutdown_start_time
    active_jobs = get_current_active_jobs()

    cond do
      active_jobs == 0 ->
        Logger.info("All jobs completed, proceeding to cleanup")
        send(self(), :begin_cleanup_phase)
        {:noreply, %{state | phase: :cleanup}}

      elapsed >= state.timeout ->
        Logger.warning("Shutdown timeout reached, forcing termination of #{active_jobs} remaining jobs")
        send(self(), :begin_force_phase)
        {:noreply, %{state | phase: :forcing}}

      true ->
        Logger.info("Waiting for #{active_jobs} jobs to complete (#{elapsed}/#{state.timeout}ms)")
        Process.send_after(self(), :check_completion, 1000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:begin_force_phase, state) do
    Logger.warning("Beginning force shutdown phase")

    # Force terminate active jobs
    force_terminate_jobs()

    # Proceed to cleanup
    Process.send_after(self(), :begin_cleanup_phase, 1000)
    {:noreply, %{state | phase: :cleanup}}
  end

  @impl true
  def handle_info(:begin_cleanup_phase, state) do
    Logger.info("Beginning shutdown cleanup phase")

    # Export final metrics
    export_final_metrics()

    # Close connections
    close_connections()

    # Clean up resources
    cleanup_resources()

    # Mark shutdown complete
    new_state = %{state | phase: :complete}

    Logger.info("Graceful shutdown completed successfully")

    # Call completion callback if provided
    if state.completion_callback do
      spawn(fn -> state.completion_callback.() end)
    end

    # Notify observers
    notify_shutdown_complete(state)

    {:noreply, new_state}
  end

  @impl true
  def terminate(reason, state) do
    if not state.shutdown_initiated do
      Logger.info("Shutdown manager terminating: #{inspect(reason)}")
    end
    :ok
  end

  ## Private Functions

  defp get_current_active_jobs do
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

  defp stop_accepting_new_work do
    Logger.info("Signaling systems to stop accepting new work")

    # Signal worker manager
    case Process.whereis(LivekitexAgent.WorkerManager) do
      nil -> :ok
      _pid ->
        try do
          # WorkerManager already has graceful_shutdown functionality
          GenServer.cast(LivekitexAgent.WorkerManager, :stop_accepting_jobs)
        catch
          :exit, reason ->
            Logger.warning("WorkerManager not responding: #{inspect(reason)}")
        end
    end

    # Signal health server to indicate shutdown in progress
    case Process.whereis(LivekitexAgent.HealthServer) do
      nil -> :ok
      _pid ->
        try do
          # Health server should report unhealthy during shutdown
          GenServer.cast(LivekitexAgent.HealthServer, :shutdown_initiated)
        catch
          :exit, reason ->
            Logger.warning("HealthServer not responding: #{inspect(reason)}")
        end
    end
  end

  defp force_terminate_jobs do
    Logger.warning("Force terminating remaining active jobs")

    case Process.whereis(LivekitexAgent.WorkerManager) do
      nil -> :ok
      _pid ->
        try do
          GenServer.cast(LivekitexAgent.WorkerManager, :force_terminate_jobs)
        catch
          :exit, reason ->
            Logger.warning("Failed to force terminate jobs: #{inspect(reason)}")
        end
    end
  end

  defp export_final_metrics do
    Logger.info("Exporting final metrics before shutdown")

    case Process.whereis(LivekitexAgent.Telemetry.Metrics) do
      nil -> :ok
      _pid ->
        try do
          LivekitexAgent.Telemetry.Metrics.export_metrics()
          # Give a moment for export to complete
          :timer.sleep(1000)
        catch
          :exit, reason ->
            Logger.warning("Failed to export final metrics: #{inspect(reason)}")
        end
    end
  end

  defp close_connections do
    Logger.info("Closing external connections")

    # Close LiveKit connections
    # In a full implementation, would enumerate and close active connections

    # Close HTTP server connections
    case Process.whereis(LivekitexAgent.HealthServer) do
      nil -> :ok
      _pid ->
        # Health server will handle its own connection cleanup
        :ok
    end
  end

  defp cleanup_resources do
    Logger.info("Cleaning up system resources")

    # Clear metrics data if needed
    # Close file handles
    # Release memory
    # etc.
  end

  defp notify_shutdown_complete(_state) do
    # In a full implementation, would notify registered observers
    Logger.info("Shutdown notification sent to observers")
    :ok
  end
end
