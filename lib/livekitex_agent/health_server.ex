defmodule LivekitexAgent.HealthServer do
  @moduledoc """
  HTTP server providing health check endpoints and system metrics.

  Provides the following endpoints:
  - GET /health - Basic health check
  - GET /health/ready - Readiness probe for Kubernetes
  - GET /health/live - Liveness probe for Kubernetes
  - GET /metrics - Prometheus-compatible metrics
  - GET /status - Detailed system status

  The server uses a simple HTTP server implementation for minimal overhead
  and fast startup times. It's designed to be lightweight and reliable
  for monitoring and orchestration systems.
  """

  use GenServer
  require Logger

  @default_port 8080
  @default_host "0.0.0.0"

  defstruct [
    :port,
    :host,
    :socket,
    :started_at,
    :health_checks,
    :metrics_collectors,
    :request_count,
    :last_request
  ]

  @type health_status :: :healthy | :degraded | :unhealthy

  @type health_check :: %{
    name: String.t(),
    status: health_status(),
    message: String.t(),
    last_check: DateTime.t(),
    duration_ms: non_neg_integer()
  }

  ## Client API

  @doc """
  Starts the health server GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current health status.
  """
  def get_health_status do
    GenServer.call(__MODULE__, :get_health_status)
  end

  @doc """
  Gets system metrics.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Registers a custom health check function.
  """
  def register_health_check(name, check_fun) when is_function(check_fun, 0) do
    GenServer.call(__MODULE__, {:register_health_check, name, check_fun})
  end

  @doc """
  Registers a custom metrics collector function.
  """
  def register_metrics_collector(name, collector_fun) when is_function(collector_fun, 0) do
    GenServer.call(__MODULE__, {:register_metrics_collector, name, collector_fun})
  end

  @doc """
  Gets the server's listening port.
  """
  def get_port do
    GenServer.call(__MODULE__, :get_port)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, @default_port)
    host = Keyword.get(opts, :host, @default_host) |> to_charlist()

    state = %__MODULE__{
      port: port,
      host: host,
      socket: nil,
      started_at: DateTime.utc_now(),
      health_checks: %{},
      metrics_collectors: %{},
      request_count: 0,
      last_request: nil
    }

    case start_http_server(state) do
      {:ok, socket} ->
        new_state = %{state | socket: socket}
        Logger.info("Health server started on #{host}:#{port}")
        {:ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to start health server: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_health_status, _from, state) do
    health_status = perform_health_checks(state)
    {:reply, health_status, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = collect_metrics(state)
    {:reply, metrics, state}
  end

  @impl true
  def handle_call({:register_health_check, name, check_fun}, _from, state) do
    new_checks = Map.put(state.health_checks, name, check_fun)
    new_state = %{state | health_checks: new_checks}
    Logger.info("Registered health check: #{name}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:register_metrics_collector, name, collector_fun}, _from, state) do
    new_collectors = Map.put(state.metrics_collectors, name, collector_fun)
    new_state = %{state | metrics_collectors: new_collectors}
    Logger.info("Registered metrics collector: #{name}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_port, _from, state) do
    {:reply, state.port, state}
  end

  @impl true
  def handle_info({:tcp, socket, request}, state) do
    spawn(fn -> handle_http_request(socket, request, state) end)
    :inet.setopts(socket, active: :once)

    new_state = %{state |
      request_count: state.request_count + 1,
      last_request: DateTime.utc_now()
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    Logger.info("Health server client disconnected")
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_error, _socket, reason}, state) do
    Logger.warning("Health server TCP error: #{inspect(reason)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    if state.socket do
      :gen_tcp.close(state.socket)
    end
    Logger.info("Health server terminating: #{inspect(reason)}")
    :ok
  end

  ## Private Functions

  defp start_http_server(state) do
    options = [
      :binary,
      {:packet, :http_bin},
      {:active, :once},
      {:reuseaddr, true},
      {:backlog, 128}
    ]

    case :gen_tcp.listen(state.port, options) do
      {:ok, listen_socket} ->
        spawn_link(fn -> accept_connections(listen_socket, state) end)
        {:ok, listen_socket}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp accept_connections(listen_socket, state) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        :inet.setopts(client_socket, active: :once)
        send(self(), {:tcp, client_socket, nil})
        accept_connections(listen_socket, state)

      {:error, reason} ->
        Logger.error("Accept error: #{inspect(reason)}")
        accept_connections(listen_socket, state)
    end
  end

  defp handle_http_request(socket, _request, state) do
    # Simple HTTP request handling - in production you'd use a proper HTTP library
    response = case parse_request_path(_request) do
      "/health" -> handle_health_endpoint(state)
      "/health/ready" -> handle_readiness_endpoint(state)
      "/health/live" -> handle_liveness_endpoint(state)
      "/metrics" -> handle_metrics_endpoint(state)
      "/status" -> handle_status_endpoint(state)
      _ -> handle_not_found()
    end

    :gen_tcp.send(socket, response)
    :gen_tcp.close(socket)
  end

  defp parse_request_path(nil), do: "/"
  defp parse_request_path(_), do: "/health"  # Simplified for now

  defp handle_health_endpoint(state) do
    health_status = perform_health_checks(state)
    status_code = if health_status.overall_status == :healthy, do: 200, else: 503

    response_body = Jason.encode!(health_status)
    build_http_response(status_code, response_body, "application/json")
  end

  defp handle_readiness_endpoint(state) do
    # Readiness check - can the service handle requests?
    ready = check_readiness(state)
    status_code = if ready, do: 200, else: 503

    response_body = Jason.encode!(%{ready: ready, timestamp: DateTime.utc_now()})
    build_http_response(status_code, response_body, "application/json")
  end

  defp handle_liveness_endpoint(state) do
    # Liveness check - is the service running?
    alive = check_liveness(state)
    status_code = if alive, do: 200, else: 503

    response_body = Jason.encode!(%{alive: alive, timestamp: DateTime.utc_now()})
    build_http_response(status_code, response_body, "application/json")
  end

  defp handle_metrics_endpoint(state) do
    metrics = collect_metrics(state)
    # Convert to Prometheus format
    prometheus_text = format_prometheus_metrics(metrics)
    build_http_response(200, prometheus_text, "text/plain")
  end

  defp handle_status_endpoint(state) do
    status = %{
      health: perform_health_checks(state),
      metrics: collect_metrics(state),
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.started_at),
      request_count: state.request_count,
      last_request: state.last_request
    }

    response_body = Jason.encode!(status)
    build_http_response(200, response_body, "application/json")
  end

  defp handle_not_found do
    response_body = Jason.encode!(%{error: "Not Found"})
    build_http_response(404, response_body, "application/json")
  end

  defp build_http_response(status_code, body, content_type) do
    status_text = case status_code do
      200 -> "OK"
      404 -> "Not Found"
      503 -> "Service Unavailable"
      _ -> "Unknown"
    end

    """
    HTTP/1.1 #{status_code} #{status_text}\r
    Content-Type: #{content_type}\r
    Content-Length: #{byte_size(body)}\r
    Connection: close\r
    \r
    #{body}
    """
  end

  defp perform_health_checks(state) do
    default_checks = %{
      "system" => fn -> check_system_health() end,
      "memory" => fn -> check_memory_health() end
    }

    all_checks = Map.merge(default_checks, state.health_checks)

    results = Enum.map(all_checks, fn {name, check_fun} ->
      start_time = System.monotonic_time(:millisecond)

      result = try do
        check_fun.()
      rescue
        e -> {:error, e.message}
      catch
        :exit, reason -> {:error, "Exit: #{inspect(reason)}"}
      end

      duration = System.monotonic_time(:millisecond) - start_time

      {name, format_health_check_result(result, duration)}
    end)

    checks = Enum.into(results, %{})
    overall_status = determine_overall_status(checks)

    %{
      overall_status: overall_status,
      checks: checks,
      timestamp: DateTime.utc_now()
    }
  end

  defp check_system_health do
    # Basic system health check
    if Process.whereis(LivekitexAgent.Application) do
      {:ok, "Application running"}
    else
      {:error, "Application not running"}
    end
  end

  defp check_memory_health do
    # Memory usage health check
    memory_bytes = :erlang.memory(:total)
    memory_mb = div(memory_bytes, 1024 * 1024)

    if memory_mb < 1000 do  # Under 1GB
      {:ok, "Memory usage normal: #{memory_mb}MB"}
    else
      {:warning, "High memory usage: #{memory_mb}MB"}
    end
  end

  defp check_readiness(state) do
    # Service is ready if it can handle requests
    health_status = perform_health_checks(state)
    health_status.overall_status != :unhealthy
  end

  defp check_liveness(_state) do
    # Service is alive if the GenServer is running
    Process.alive?(self())
  end

  defp format_health_check_result({:ok, message}, duration) do
    %{status: :healthy, message: message, duration_ms: duration, last_check: DateTime.utc_now()}
  end

  defp format_health_check_result({:warning, message}, duration) do
    %{status: :degraded, message: message, duration_ms: duration, last_check: DateTime.utc_now()}
  end

  defp format_health_check_result({:error, message}, duration) do
    %{status: :unhealthy, message: message, duration_ms: duration, last_check: DateTime.utc_now()}
  end

  defp determine_overall_status(checks) do
    statuses = checks |> Map.values() |> Enum.map(& &1.status)

    cond do
      Enum.any?(statuses, &(&1 == :unhealthy)) -> :unhealthy
      Enum.any?(statuses, &(&1 == :degraded)) -> :degraded
      true -> :healthy
    end
  end

  defp collect_metrics(state) do
    default_metrics = %{
      "http_requests_total" => state.request_count,
      "uptime_seconds" => DateTime.diff(DateTime.utc_now(), state.started_at),
      "memory_bytes" => :erlang.memory(:total),
      "process_count" => :erlang.system_info(:process_count)
    }

    custom_metrics = Enum.reduce(state.metrics_collectors, %{}, fn {name, collector_fun}, acc ->
      try do
        metrics = collector_fun.()
        Map.merge(acc, metrics)
      rescue
        e ->
          Logger.error("Error collecting metrics from #{name}: #{inspect(e)}")
          acc
      end
    end)

    Map.merge(default_metrics, custom_metrics)
  end

  defp format_prometheus_metrics(metrics) do
    Enum.map(metrics, fn {name, value} ->
      "# TYPE #{name} gauge\n#{name} #{value}"
    end)
    |> Enum.join("\n")
  end
end
