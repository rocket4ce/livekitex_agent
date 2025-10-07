defmodule LivekitexAgent.WorkerOptions do
  @moduledoc """
  Configuration object for worker behavior and job execution.

  WorkerOptions manages:
  - Entry point function called when a job is assigned
  - Request handling logic to decide if worker should handle a job
  - Process management including job executor type, memory limits, timeouts
  - Load balancing with load calculation and thresholds
  - Connection settings including LiveKit server URL and API credentials
  - Agent settings including name, permissions, and worker type
  """

  defstruct [
    :entry_point,
    :request_handler,
    :job_executor_type,
    :memory_limit,
    :timeout,
    :load_threshold,
    :load_calculator,
    :server_url,
    :api_key,
    :api_secret,
    :agent_name,
    :permissions,
    :worker_type,
    :worker_id,
    :metadata,
    :health_check_interval,
    :max_concurrent_jobs,
    :graceful_shutdown_timeout,
    :log_level,
    # Enterprise load balancing features
    :load_balancer_strategy,
    :worker_pool_size,
    :job_queue_size,
    :circuit_breaker_config,
    :auto_scaling_enabled,
    :scaling_metrics_window,
    :min_workers,
    :max_workers,
    :cpu_threshold,
    :memory_threshold,
    :queue_threshold,
    :backpressure_enabled,
    :rate_limiting_config
  ]

  @type job_executor_type :: :process | :task | :genserver
  @type worker_type :: :voice_agent | :multimodal_agent | :text_agent | :custom
  @type log_level ::
          :emergency | :alert | :critical | :error | :warning | :notice | :info | :debug
  @type load_balancer_strategy :: :round_robin | :least_connections | :weighted_round_robin | :load_based
  @type circuit_breaker_config :: %{
          failure_threshold: pos_integer(),
          timeout: pos_integer(),
          recovery_time: pos_integer()
        }
  @type rate_limiting_config :: %{
          max_requests: pos_integer(),
          window_ms: pos_integer(),
          burst_size: pos_integer()
        }

  @type t :: %__MODULE__{
          entry_point: (LivekitexAgent.JobContext.t() -> any()),
          request_handler: (map() -> boolean()),
          job_executor_type: job_executor_type(),
          memory_limit: pos_integer() | nil,
          timeout: pos_integer(),
          load_threshold: float(),
          load_calculator: (-> float()),
          server_url: String.t(),
          api_key: String.t(),
          api_secret: String.t(),
          agent_name: String.t(),
          permissions: list(atom()),
          worker_type: worker_type(),
          worker_id: String.t(),
          metadata: map(),
          health_check_interval: pos_integer(),
          max_concurrent_jobs: pos_integer(),
          graceful_shutdown_timeout: pos_integer(),
          log_level: log_level(),
          # Enterprise load balancing features
          load_balancer_strategy: load_balancer_strategy(),
          worker_pool_size: pos_integer(),
          job_queue_size: pos_integer(),
          circuit_breaker_config: circuit_breaker_config() | nil,
          auto_scaling_enabled: boolean(),
          scaling_metrics_window: pos_integer(),
          min_workers: pos_integer(),
          max_workers: pos_integer(),
          cpu_threshold: float(),
          memory_threshold: float(),
          queue_threshold: float(),
          backpressure_enabled: boolean(),
          rate_limiting_config: rate_limiting_config() | nil
        }

  @doc """
  Creates new worker options with the given configuration.

  ## Options
  - `:entry_point` - Function called when a job is assigned (required)
  - `:request_handler` - Function to decide if worker should handle a job
  - `:job_executor_type` - Type of job executor (:process, :task, :genserver)
  - `:memory_limit` - Memory limit in MB for job processes
  - `:timeout` - Job timeout in milliseconds
  - `:load_threshold` - Maximum load before rejecting jobs (0.0-1.0)
  - `:server_url` - LiveKit server URL
  - `:api_key` - LiveKit API key
  - `:api_secret` - LiveKit API secret
  - `:agent_name` - Name of the agent
  - `:worker_type` - Type of worker (:voice_agent, :multimodal_agent, etc.)
  - `:max_concurrent_jobs` - Maximum number of concurrent jobs

  ## Example
      iex> LivekitexAgent.WorkerOptions.new(
      ...>   entry_point: &MyAgent.handle_job/1,
      ...>   agent_name: "my_voice_assistant",
      ...>   worker_type: :voice_agent,
      ...>   max_concurrent_jobs: 5,
      ...>   server_url: "wss://myapp.livekit.cloud",
      ...>   api_key: "my-api-key"
      ...> )
  """
  def new(opts \\ []) do
    %__MODULE__{
      entry_point: Keyword.fetch!(opts, :entry_point),
      request_handler: Keyword.get(opts, :request_handler, &default_request_handler/1),
      job_executor_type: Keyword.get(opts, :job_executor_type, :process),
      # 512 MB default
      memory_limit: Keyword.get(opts, :memory_limit, 512),
      # 5 minutes default
      timeout: Keyword.get(opts, :timeout, 300_000),
      load_threshold: Keyword.get(opts, :load_threshold, 0.8),
      load_calculator: Keyword.get(opts, :load_calculator, &default_load_calculator/0),
      server_url: Keyword.get(opts, :server_url, "ws://localhost:7880"),
      api_key: Keyword.get(opts, :api_key, ""),
      api_secret: Keyword.get(opts, :api_secret, ""),
      agent_name: Keyword.get(opts, :agent_name, "elixir_agent"),
      permissions: Keyword.get(opts, :permissions, [:room_join, :room_admin]),
      worker_type: Keyword.get(opts, :worker_type, :voice_agent),
      worker_id: Keyword.get(opts, :worker_id, generate_worker_id()),
      metadata: Keyword.get(opts, :metadata, %{}),
      # 30 seconds
      health_check_interval: Keyword.get(opts, :health_check_interval, 30_000),
      max_concurrent_jobs: Keyword.get(opts, :max_concurrent_jobs, 10),
      # 30 seconds
      graceful_shutdown_timeout: Keyword.get(opts, :graceful_shutdown_timeout, 30_000),
      log_level: Keyword.get(opts, :log_level, :info),
      # Enterprise load balancing defaults
      load_balancer_strategy: Keyword.get(opts, :load_balancer_strategy, :load_based),
      worker_pool_size: Keyword.get(opts, :worker_pool_size, System.schedulers_online()),
      job_queue_size: Keyword.get(opts, :job_queue_size, 1000),
      circuit_breaker_config: Keyword.get(opts, :circuit_breaker_config),
      auto_scaling_enabled: Keyword.get(opts, :auto_scaling_enabled, false),
      # 5 minute window for scaling decisions
      scaling_metrics_window: Keyword.get(opts, :scaling_metrics_window, 300_000),
      min_workers: Keyword.get(opts, :min_workers, 1),
      max_workers: Keyword.get(opts, :max_workers, System.schedulers_online() * 4),
      cpu_threshold: Keyword.get(opts, :cpu_threshold, 0.8),
      memory_threshold: Keyword.get(opts, :memory_threshold, 0.85),
      queue_threshold: Keyword.get(opts, :queue_threshold, 0.9),
      backpressure_enabled: Keyword.get(opts, :backpressure_enabled, true),
      rate_limiting_config: Keyword.get(opts, :rate_limiting_config)
    }
  end

  @doc """
  Validates worker options configuration.
  """
  def validate(%__MODULE__{} = options) do
    validations = [
      validate_entry_point(options.entry_point),
      validate_memory_limit(options.memory_limit),
      validate_timeout(options.timeout),
      validate_load_threshold(options.load_threshold),
      validate_server_url(options.server_url),
      validate_max_concurrent_jobs(options.max_concurrent_jobs),
      validate_worker_type(options.worker_type),
      validate_log_level(options.log_level)
    ]

    case Enum.find(validations, &(elem(&1, 0) == :error)) do
      nil -> {:ok, options}
      error -> error
    end
  end

  @doc """
  Checks if the worker should handle a job request based on current load and configuration.
  """
  def should_handle_job?(%__MODULE__{} = options, job_request) do
    cond do
      current_load(options) >= options.load_threshold ->
        {:reject, :load_too_high}

      get_concurrent_jobs_count() >= options.max_concurrent_jobs ->
        {:reject, :max_jobs_reached}

      not options.request_handler.(job_request) ->
        {:reject, :request_handler_declined}

      true ->
        {:accept, :ok}
    end
  end

  @doc """
  Gets current worker load (0.0 to 1.0).
  """
  def current_load(%__MODULE__{} = options) do
    options.load_calculator.()
  end

  @doc """
  Gets worker configuration as a map suitable for registration.
  """
  def to_registration_config(%__MODULE__{} = options) do
    %{
      worker_id: options.worker_id,
      agent_name: options.agent_name,
      worker_type: options.worker_type,
      permissions: options.permissions,
      max_concurrent_jobs: options.max_concurrent_jobs,
      metadata: options.metadata
    }
  end

  @doc """
  Updates worker options with new values.
  """
  def update(%__MODULE__{} = options, updates) when is_list(updates) do
    Enum.reduce(updates, options, fn {key, value}, acc ->
      Map.put(acc, key, value)
    end)
  end

  @doc """
  Creates connection configuration for LiveKit server.
  """
  def connection_config(%__MODULE__{} = options) do
    %{
      server_url: options.server_url,
      api_key: options.api_key,
      api_secret: options.api_secret,
      agent_name: options.agent_name
    }
  end

  @doc """
  Creates job execution configuration.
  """
  def execution_config(%__MODULE__{} = options) do
    %{
      executor_type: options.job_executor_type,
      memory_limit: options.memory_limit,
      timeout: options.timeout,
      entry_point: options.entry_point
    }
  end

  @doc """
  Gets health check configuration.
  """
  def health_config(%__MODULE__{} = options) do
    %{
      interval: options.health_check_interval,
      load_threshold: options.load_threshold,
      load_calculator: options.load_calculator
    }
  end

  @doc """
  Creates a default request handler that accepts all requests.
  """
  def default_request_handler(_job_request), do: true

  @doc """
  Creates a load-based request handler.
  """
  def load_based_request_handler(max_load \\ 0.8) do
    fn _job_request ->
      default_load_calculator() <= max_load
    end
  end

  @doc """
  Creates a room-type based request handler.
  """
  def room_type_request_handler(accepted_types) when is_list(accepted_types) do
    fn %{room_type: room_type} ->
      room_type in accepted_types
    end
  end

  @doc """
  Creates a circuit breaker configuration.
  """
  def circuit_breaker_config(opts \\ []) do
    %{
      failure_threshold: Keyword.get(opts, :failure_threshold, 5),
      timeout: Keyword.get(opts, :timeout, 60_000),
      recovery_time: Keyword.get(opts, :recovery_time, 30_000)
    }
  end

  @doc """
  Creates a rate limiting configuration.
  """
  def rate_limiting_config(opts \\ []) do
    %{
      max_requests: Keyword.get(opts, :max_requests, 100),
      window_ms: Keyword.get(opts, :window_ms, 60_000),
      burst_size: Keyword.get(opts, :burst_size, 20)
    }
  end

  @doc """
  Calculates if auto-scaling is needed based on current metrics.
  """
  def should_scale?(%__MODULE__{auto_scaling_enabled: false}), do: :no_scaling

  def should_scale?(%__MODULE__{} = options) do
    current_load = current_load(options)
    queue_load = get_queue_load()
    cpu_load = get_cpu_load()
    memory_load = get_memory_load()

    cond do
      cpu_load > options.cpu_threshold or
      memory_load > options.memory_threshold or
      queue_load > options.queue_threshold ->
        {:scale_up, %{cpu: cpu_load, memory: memory_load, queue: queue_load}}

      current_load < 0.3 and cpu_load < 0.4 and memory_load < 0.4 ->
        {:scale_down, %{cpu: cpu_load, memory: memory_load, queue: queue_load}}

      true ->
        :no_scaling
    end
  end

  @doc """
  Gets the recommended worker count based on load balancer strategy.
  """
  def get_recommended_worker_count(%__MODULE__{} = options) do
    case options.load_balancer_strategy do
      :round_robin ->
        min(options.max_workers, max(options.min_workers, options.worker_pool_size))

      :least_connections ->
        # Scale based on connection load
        connection_load = get_connection_load()
        recommended = trunc(connection_load * options.worker_pool_size) + 1
        min(options.max_workers, max(options.min_workers, recommended))

      :weighted_round_robin ->
        # Scale based on weighted load distribution
        weighted_load = get_weighted_load()
        recommended = trunc(weighted_load * options.worker_pool_size) + 1
        min(options.max_workers, max(options.min_workers, recommended))

      :load_based ->
        # Scale based on overall system load
        system_load = current_load(options)
        recommended = trunc(system_load * options.worker_pool_size * 1.5) + 1
        min(options.max_workers, max(options.min_workers, recommended))
    end
  end

  @doc """
  Default load calculator based on system metrics.
  """
  def default_load_calculator do
    # Calculate load based on CPU, memory, and concurrent jobs
    cpu_load = get_cpu_load()
    memory_load = get_memory_load()
    # Normalize to max 10 jobs
    job_load = get_concurrent_jobs_count() / 10.0

    max(cpu_load, max(memory_load, job_load))
  end

  # Private functions

  defp validate_entry_point(entry_point) when is_function(entry_point, 1), do: {:ok, :valid}
  defp validate_entry_point(_), do: {:error, :invalid_entry_point}

  defp validate_memory_limit(nil), do: {:ok, :valid}
  defp validate_memory_limit(limit) when is_integer(limit) and limit > 0, do: {:ok, :valid}
  defp validate_memory_limit(_), do: {:error, :invalid_memory_limit}

  defp validate_timeout(timeout) when is_integer(timeout) and timeout > 0, do: {:ok, :valid}
  defp validate_timeout(_), do: {:error, :invalid_timeout}

  defp validate_load_threshold(threshold)
       when is_float(threshold) and threshold >= 0 and threshold <= 1,
       do: {:ok, :valid}

  defp validate_load_threshold(_), do: {:error, :invalid_load_threshold}

  defp validate_server_url(url) when is_binary(url) and byte_size(url) > 0, do: {:ok, :valid}
  defp validate_server_url(_), do: {:error, :invalid_server_url}

  defp validate_max_concurrent_jobs(count) when is_integer(count) and count > 0, do: {:ok, :valid}
  defp validate_max_concurrent_jobs(_), do: {:error, :invalid_max_concurrent_jobs}

  defp validate_worker_type(type)
       when type in [:voice_agent, :multimodal_agent, :text_agent, :custom],
       do: {:ok, :valid}

  defp validate_worker_type(_), do: {:error, :invalid_worker_type}

  defp validate_log_level(level)
       when level in [:emergency, :alert, :critical, :error, :warning, :notice, :info, :debug],
       do: {:ok, :valid}

  defp validate_log_level(_), do: {:error, :invalid_log_level}

  defp generate_worker_id do
    hostname = :inet.gethostname() |> elem(1) |> to_string()
    timestamp = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "worker_#{hostname}_#{timestamp}_#{random}"
  end

  defp get_concurrent_jobs_count do
    # This would typically query a job registry or supervisor
    # For now, return a mock value
    # Rough approximation
    Process.list() |> length() |> div(10)
  end

  defp get_cpu_load do
    # Simple CPU load estimation based on process count vs schedulers
    try do
      processes = length(Process.list())
      schedulers = :erlang.system_info(:schedulers_online)

      # Estimate load as processes per scheduler, with some reasonable scaling
      # Assume 50 processes per scheduler is moderate load
      load = processes / (schedulers * 50)
      min(load, 1.0)
    rescue
      _ ->
        # Default moderate load if unable to determine
        0.5
    end
  end

  defp get_memory_load do
    # Memory load estimation based on Erlang memory info
    try do
      memory_info = :erlang.memory()
      total = Keyword.get(memory_info, :total, 1)
      processes = Keyword.get(memory_info, :processes, 0)
      system = Keyword.get(memory_info, :system, 0)

      # Estimate load as (processes + system) / total with some reasonable scaling
      used = processes + system

      case {used, total} do
        {u, t} when is_number(u) and is_number(t) and t > 0 ->
          min(u / t, 1.0)

        _ ->
          0.5
      end
    rescue
      _ -> 0.5
    end
  end

  defp get_queue_load do
    # Estimate queue load based on message queue lengths
    try do
      processes = Process.list()
      total_queue_len =
        processes
        |> Enum.map(fn pid ->
          case Process.info(pid, :message_queue_len) do
            {:message_queue_len, len} -> len
            _ -> 0
          end
        end)
        |> Enum.sum()

      # Normalize to reasonable scale (assume 10 messages per process is moderate load)
      expected_load = length(processes) * 10

      case expected_load do
        0 -> 0.0
        _ -> min(total_queue_len / expected_load, 1.0)
      end
    rescue
      _ -> 0.3
    end
  end

  defp get_connection_load do
    # Estimate connection load based on network activity
    # This would integrate with LiveKit connection metrics
    try do
      # Placeholder - would need actual LiveKit metrics
      port_count = length(Port.list())
      # Assume 5 ports per connection is moderate load
      min(port_count / 50.0, 1.0)
    rescue
      _ -> 0.4
    end
  end

  defp get_weighted_load do
    # Calculate weighted load combining multiple factors
    cpu_weight = 0.4
    memory_weight = 0.3
    queue_weight = 0.2
    connection_weight = 0.1

    cpu_load = get_cpu_load()
    memory_load = get_memory_load()
    queue_load = get_queue_load()
    connection_load = get_connection_load()

    (cpu_load * cpu_weight) +
    (memory_load * memory_weight) +
    (queue_load * queue_weight) +
    (connection_load * connection_weight)
  end
end
