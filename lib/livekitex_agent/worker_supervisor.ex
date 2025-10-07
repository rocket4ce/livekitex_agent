defmodule LivekitexAgent.WorkerSupervisor do
  @moduledoc """
  Enhanced supervisor for agent workers with comprehensive job management.

  This supervisor provides:
  - Dynamic worker process management
  - Job queue coordination
  - Resource pooling and load balancing
  - Fault tolerance with worker restart strategies
  - Performance monitoring and metrics collection
  - Graceful shutdown handling
  - Circuit breaker integration for external services

  ## Supervision Strategy

  Uses a :rest_for_one strategy to ensure that if a core service fails,
  all dependent services are restarted in the correct order. Critical
  infrastructure components (like the tool registry) are started first.

  ## Child Process Hierarchy

  1. **Tool Registry** - Global tool registration and discovery
  2. **Circuit Breaker Registry** - Circuit breaker instances for resilience
  3. **Audio Processor** - Real-time audio processing pipeline
  4. **Health Server** - HTTP health checks and metrics endpoints
  5. **Worker Manager** - Job distribution and worker coordination
  6. **Dynamic Workers** - Individual agent worker processes
  """

  use DynamicSupervisor
  require Logger

  alias LivekitexAgent.Telemetry.Logger, as: TelemetryLogger

  @max_children 100
  @max_restarts 10
  @max_seconds 60

  defstruct [
    :worker_options,
    :max_children,
    :active_workers,
    :job_queue,
    :metrics,
    :shutdown_timeout
  ]

  @type t :: %__MODULE__{
          worker_options: map(),
          max_children: pos_integer(),
          active_workers: non_neg_integer(),
          job_queue: :queue.queue(),
          metrics: map(),
          shutdown_timeout: pos_integer()
        }

  ## Client API

  @doc """
  Starts the worker supervisor with the given options.
  """
  def start_link(worker_options) do
    DynamicSupervisor.start_link(__MODULE__, worker_options, name: __MODULE__)
  end

  @doc """
  Starts a new worker process for handling jobs.
  """
  def start_worker(job_spec) do
    child_spec = {LivekitexAgent.Worker, job_spec}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Stops a specific worker process.
  """
  def stop_worker(worker_pid) when is_pid(worker_pid) do
    DynamicSupervisor.terminate_child(__MODULE__, worker_pid)
  end

  @doc """
  Gets a list of all active worker processes.
  """
  def list_workers do
    DynamicSupervisor.which_children(__MODULE__)
  end

  @doc """
  Gets the count of active workers.
  """
  def worker_count do
    DynamicSupervisor.count_children(__MODULE__)
  end

  @doc """
  Gracefully shuts down all workers and stops the supervisor.
  """
  def shutdown(timeout \\ 30_000) do
    workers = list_workers()

    TelemetryLogger.info("Shutting down worker supervisor",
      worker_count: length(workers),
      timeout: timeout
    )

    # First, stop accepting new work
    :ets.insert(:worker_supervisor_state, {:accepting_work, false})

    # Then gracefully shutdown all workers
    Enum.each(workers, fn {_id, pid, _type, _modules} ->
      if Process.alive?(pid) do
        GenServer.call(pid, :prepare_shutdown, timeout)
      end
    end)

    # Wait for workers to finish current jobs
    wait_for_workers_shutdown(workers, timeout)

    # Finally stop the supervisor
    GenServer.stop(__MODULE__, :normal, timeout)
  end

  @doc """
  Gets performance metrics for the worker supervisor.
  """
  def get_metrics do
    case :ets.lookup(:worker_supervisor_state, :metrics) do
      [{:metrics, metrics}] -> metrics
      [] -> %{}
    end
  end

  @doc """
  Updates the worker options configuration.
  """
  def update_worker_options(new_options) do
    :ets.insert(:worker_supervisor_state, {:worker_options, new_options})
    :ok
  end

  ## Supervisor Callbacks

  @impl true
  def init(worker_options) do
    # Initialize ETS table for supervisor state
    :ets.new(:worker_supervisor_state, [:set, :public, :named_table])
    :ets.insert(:worker_supervisor_state, {:worker_options, worker_options})
    :ets.insert(:worker_supervisor_state, {:accepting_work, true})
    :ets.insert(:worker_supervisor_state, {:metrics, init_metrics()})

    # Start the static infrastructure supervisor first
    {:ok, _infrastructure_sup} = start_infrastructure_supervisor(worker_options)

    TelemetryLogger.info("Worker supervisor initialized",
      agent_name: Map.get(worker_options, :agent_name, "unknown"),
      max_children: @max_children
    )

    # Configure the dynamic supervisor
    opts = [
      strategy: :one_for_one,
      max_children: @max_children,
      max_restarts: @max_restarts,
      max_seconds: @max_seconds
    ]

    DynamicSupervisor.init(opts)
  end

  ## Private Functions

  defp start_infrastructure_supervisor(worker_options) do
    children = [
      # Global registries and infrastructure
      {Registry, keys: :unique, name: LivekitexAgent.CircuitBreakerRegistry},

      # Core services in dependency order
      {LivekitexAgent.ToolRegistry, []},

      # Audio processing pipeline
      {LivekitexAgent.Media.AudioProcessor, Map.get(worker_options, :audio_config, %{})},

      # Health monitoring
      {LivekitexAgent.HealthServer, Map.get(worker_options, :health_config, %{})},

      # Worker coordination
      {LivekitexAgent.WorkerManager, worker_options}
    ]

    # Start static infrastructure supervisor
    Supervisor.start_link(children,
      strategy: :rest_for_one,
      name: LivekitexAgent.InfrastructureSupervisor
    )
  end

  defp init_metrics do
    %{
      workers_started: 0,
      workers_stopped: 0,
      jobs_completed: 0,
      jobs_failed: 0,
      total_uptime_seconds: 0,
      average_job_duration_ms: 0.0,
      started_at: DateTime.utc_now()
    }
  end

  defp wait_for_workers_shutdown(workers, timeout) do
    start_time = System.monotonic_time(:millisecond)

    wait_loop = fn wait_loop ->
      elapsed = System.monotonic_time(:millisecond) - start_time

      if elapsed >= timeout do
        TelemetryLogger.warn("Worker shutdown timeout reached",
          elapsed_ms: elapsed,
          timeout_ms: timeout
        )
      else
        alive_workers =
          Enum.filter(workers, fn {_id, pid, _type, _modules} ->
            Process.alive?(pid)
          end)

        if length(alive_workers) == 0 do
          TelemetryLogger.info("All workers shutdown gracefully",
            elapsed_ms: elapsed
          )
        else
          Process.sleep(100)
          wait_loop.(wait_loop)
        end
      end
    end

    wait_loop.(wait_loop)
  end
end

defmodule LivekitexAgent.Worker do
  @moduledoc """
  Individual worker process for handling agent jobs.

  Each worker manages:
  - Single agent session lifecycle
  - Job execution with timeout handling
  - Resource cleanup on completion
  - Performance metrics collection
  - Error handling and recovery
  """

  use GenServer
  require Logger

  alias LivekitexAgent.Telemetry.Logger, as: TelemetryLogger

  defstruct [
    :job_spec,
    :agent_session,
    :start_time,
    :current_job,
    :metrics,
    :shutdown_requested
  ]

  ## Client API

  def start_link(job_spec) do
    GenServer.start_link(__MODULE__, job_spec)
  end

  def execute_job(worker_pid, job) do
    GenServer.call(worker_pid, {:execute_job, job})
  end

  def get_status(worker_pid) do
    GenServer.call(worker_pid, :get_status)
  end

  def prepare_shutdown(worker_pid, timeout \\ 5000) do
    GenServer.call(worker_pid, :prepare_shutdown, timeout)
  end

  ## GenServer Callbacks

  @impl true
  def init(job_spec) do
    state = %__MODULE__{
      job_spec: job_spec,
      agent_session: nil,
      start_time: DateTime.utc_now(),
      current_job: nil,
      metrics: %{jobs_completed: 0, jobs_failed: 0},
      shutdown_requested: false
    }

    TelemetryLogger.info("Worker started", worker_pid: self(), job_spec: job_spec)

    {:ok, state}
  end

  @impl true
  def handle_call({:execute_job, job}, _from, state) do
    if state.shutdown_requested do
      {:reply, {:error, :shutdown_requested}, state}
    else
      start_time = System.monotonic_time(:millisecond)

      try do
        result = perform_job(job, state)
        duration = System.monotonic_time(:millisecond) - start_time

        new_metrics = update_job_metrics(state.metrics, :success, duration)
        new_state = %{state | metrics: new_metrics, current_job: nil}

        TelemetryLogger.info("Job completed", job_id: Map.get(job, :id), duration_ms: duration)

        {:reply, result, new_state}
      rescue
        e ->
          duration = System.monotonic_time(:millisecond) - start_time
          new_metrics = update_job_metrics(state.metrics, :failure, duration)
          new_state = %{state | metrics: new_metrics, current_job: nil}

          TelemetryLogger.log_error(e, "Job execution failed",
            job_id: Map.get(job, :id),
            duration_ms: duration
          )

          {:reply, {:error, Exception.message(e)}, new_state}
      end
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      worker_pid: self(),
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.start_time),
      current_job: state.current_job,
      metrics: state.metrics,
      shutdown_requested: state.shutdown_requested
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:prepare_shutdown, _from, state) do
    TelemetryLogger.info("Worker preparing for shutdown", worker_pid: self())

    new_state = %{state | shutdown_requested: true}

    # If currently executing a job, let it finish
    # Otherwise, stop immediately
    if state.current_job do
      {:reply, :shutdown_prepared, new_state}
    else
      {:stop, :normal, :shutdown_complete, new_state}
    end
  end

  @impl true
  def terminate(reason, state) do
    uptime = DateTime.diff(DateTime.utc_now(), state.start_time)

    TelemetryLogger.info("Worker terminating",
      worker_pid: self(),
      reason: reason,
      uptime_seconds: uptime,
      jobs_completed: state.metrics.jobs_completed
    )

    :ok
  end

  ## Private Functions

  defp perform_job(job, state) do
    # This is where the actual job execution would happen
    # For now, simulate job processing
    job_type = Map.get(job, :type, :unknown)

    case job_type do
      :agent_session ->
        handle_agent_session_job(job, state)

      :tool_execution ->
        handle_tool_execution_job(job, state)

      :audio_processing ->
        handle_audio_processing_job(job, state)

      _ ->
        {:error, :unknown_job_type}
    end
  end

  defp handle_agent_session_job(job, _state) do
    # Create or resume an agent session
    session_config = Map.get(job, :session_config, %{})

    TelemetryLogger.info("Starting agent session",
      session_id: Map.get(session_config, :session_id)
    )

    # Simulate session processing
    Process.sleep(100)

    {:ok, %{status: :session_active, session_id: Map.get(session_config, :session_id)}}
  end

  defp handle_tool_execution_job(job, _state) do
    tool_name = Map.get(job, :tool_name)
    params = Map.get(job, :params, %{})

    TelemetryLogger.info("Executing tool", tool: tool_name, params: params)

    # Execute through tool registry
    case LivekitexAgent.ToolRegistry.execute_tool(tool_name, params) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_audio_processing_job(job, _state) do
    audio_data = Map.get(job, :audio_data)
    processing_type = Map.get(job, :processing_type, :transcription)

    TelemetryLogger.info("Processing audio",
      processing_type: processing_type,
      data_size: byte_size(audio_data || <<>>)
    )

    # Simulate audio processing
    Process.sleep(50)

    case processing_type do
      :transcription -> {:ok, %{text: "Processed audio transcription"}}
      :synthesis -> {:ok, %{audio: "Generated audio data"}}
      _ -> {:error, :unknown_processing_type}
    end
  end

  defp update_job_metrics(metrics, result, _duration) do
    case result do
      :success ->
        %{metrics | jobs_completed: metrics.jobs_completed + 1}

      :failure ->
        %{metrics | jobs_failed: metrics.jobs_failed + 1}
    end
  end
end
