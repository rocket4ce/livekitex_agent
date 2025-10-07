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

    new_state = %{
      state
      | request_count: state.request_count + 1,
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

  defp handle_http_request(socket, request_data, state) do
    # Parse HTTP request for better path detection
    response =
      case parse_http_request(request_data) do
        {:ok, method, path, _headers} ->
          handle_endpoint(method, path, state)

        {:error, _reason} ->
          # Fallback to simple health check
          handle_health_endpoint(state)
      end

    :gen_tcp.send(socket, response)
    :gen_tcp.close(socket)
  end

  defp parse_http_request(request_data) when is_binary(request_data) do
    case String.split(request_data, "\r\n", parts: 2) do
      [request_line | _] ->
        case String.split(request_line, " ", parts: 3) do
          [method, path, _version] ->
            {:ok, method, path, %{}}

          _ ->
            {:error, :invalid_request_line}
        end

      _ ->
        {:error, :no_request_line}
    end
  end

  defp parse_http_request(_), do: {:error, :invalid_request}

  defp handle_endpoint(method, path, state) do
    case {method, path} do
      {"GET", "/health"} -> handle_health_endpoint(state)
      {"GET", "/health/ready"} -> handle_readiness_endpoint(state)
      {"GET", "/health/live"} -> handle_liveness_endpoint(state)
      {"GET", "/metrics"} -> handle_metrics_endpoint(state)
      {"GET", "/status"} -> handle_status_endpoint(state)
      {"GET", "/dashboard"} -> handle_dashboard_endpoint(state)
      {"GET", "/workers"} -> handle_workers_endpoint(state)
      {"GET", "/jobs"} -> handle_jobs_endpoint(state)
      {"GET", "/config"} -> handle_config_endpoint(state)
      {"POST", "/health/check"} -> handle_manual_health_check(state)
      # Enhanced Dashboard Endpoints
      {"GET", "/dashboard/ui"} -> handle_dashboard_ui_endpoint(state)
      {"GET", "/dashboard/api/overview"} -> handle_dashboard_overview_api(state)
      {"GET", "/dashboard/api/workers"} -> handle_dashboard_workers_api(state)
      {"GET", "/dashboard/api/jobs"} -> handle_dashboard_jobs_api(state)
      {"GET", "/dashboard/api/metrics"} -> handle_dashboard_metrics_api(state)
      {"GET", "/dashboard/api/health"} -> handle_dashboard_health_api(state)
      {"GET", "/dashboard/api/system"} -> handle_dashboard_system_api(state)
      {"GET", "/dashboard/api/logs"} -> handle_dashboard_logs_api(state)
      {"GET", "/dashboard/api/alerts"} -> handle_dashboard_alerts_api(state)
      {"GET", "/dashboard/streaming/metrics"} -> handle_streaming_metrics_endpoint(state)
      {"GET", "/dashboard/streaming/logs"} -> handle_streaming_logs_endpoint(state)
      # Administrative endpoints
      {"POST", "/admin/scale"} -> handle_admin_scale_endpoint(state)
      {"POST", "/admin/restart"} -> handle_admin_restart_endpoint(state)
      {"POST", "/admin/drain"} -> handle_admin_drain_endpoint(state)
      {"GET", "/admin/backup"} -> handle_admin_backup_endpoint(state)
      _ -> handle_not_found()
    end
  end

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

  defp handle_dashboard_endpoint(state) do
    dashboard_data = %{
      system_info: get_system_info(),
      worker_status: get_worker_status(),
      job_queue_status: get_job_queue_status(),
      performance_metrics: get_performance_metrics(state),
      health_summary: perform_health_checks(state)
    }

    response_body = Jason.encode!(dashboard_data)
    build_http_response(200, response_body, "application/json")
  end

  defp handle_workers_endpoint(state) do
    worker_status = get_worker_status()
    response_body = Jason.encode!(worker_status)
    build_http_response(200, response_body, "application/json")
  end

  defp handle_jobs_endpoint(state) do
    job_status = get_job_status()
    response_body = Jason.encode!(job_status)
    build_http_response(200, response_body, "application/json")
  end

  defp handle_config_endpoint(state) do
    config_info = %{
      port: state.port,
      host: List.to_string(state.host),
      started_at: state.started_at,
      registered_health_checks: Map.keys(state.health_checks),
      registered_metrics_collectors: Map.keys(state.metrics_collectors)
    }

    response_body = Jason.encode!(config_info)
    build_http_response(200, response_body, "application/json")
  end

  defp handle_manual_health_check(state) do
    # Trigger an immediate health check
    health_status = perform_health_checks(state)
    status_code = if health_status.overall_status == :healthy, do: 200, else: 503

    response_body = Jason.encode!(health_status)
    build_http_response(status_code, response_body, "application/json")
  end

  # Enhanced Dashboard Endpoints

  @doc """
  Serves the HTML dashboard UI with interactive monitoring interface.
  """
  defp handle_dashboard_ui_endpoint(_state) do
    html_content = generate_dashboard_html()
    build_http_response(200, html_content, "text/html")
  end

  @doc """
  Provides overview API data for dashboard consumption.
  """
  defp handle_dashboard_overview_api(state) do
    overview_data = %{
      timestamp: DateTime.utc_now(),
      uptime: get_system_uptime(),
      system: %{
        status: get_overall_system_status(state),
        memory_usage: get_memory_usage(),
        cpu_usage: get_cpu_usage(),
        load_average: get_load_average()
      },
      workers: %{
        active: count_active_workers(),
        total: count_total_workers(),
        utilization: calculate_worker_utilization()
      },
      jobs: %{
        active: count_active_jobs(),
        pending: count_pending_jobs(),
        completed_today: count_completed_jobs_today(),
        success_rate: calculate_success_rate()
      },
      performance: %{
        avg_response_time: get_avg_response_time(),
        requests_per_minute: get_requests_per_minute(),
        error_rate: get_error_rate()
      }
    }

    response_body = Jason.encode!(overview_data)
    build_http_response(200, response_body, "application/json")
  end

  @doc """
  Provides detailed worker information for dashboard.
  """
  defp handle_dashboard_workers_api(_state) do
    workers_data = %{
      timestamp: DateTime.utc_now(),
      workers: get_detailed_worker_info(),
      scaling: %{
        auto_scaling_enabled: is_auto_scaling_enabled(),
        min_workers: get_min_workers(),
        max_workers: get_max_workers(),
        scale_up_threshold: get_scale_up_threshold(),
        scale_down_threshold: get_scale_down_threshold()
      },
      load_balancing: %{
        strategy: get_load_balancer_strategy(),
        distribution: get_load_distribution()
      }
    }

    response_body = Jason.encode!(workers_data)
    build_http_response(200, response_body, "application/json")
  end

  @doc """
  Provides detailed job queue information for dashboard.
  """
  defp handle_dashboard_jobs_api(_state) do
    jobs_data = %{
      timestamp: DateTime.utc_now(),
      queue_status: get_comprehensive_queue_status(),
      recent_jobs: get_recent_job_history(50),
      job_types: get_job_type_statistics(),
      performance: %{
        avg_processing_time: get_avg_job_processing_time(),
        jobs_per_hour: get_jobs_per_hour(),
        peak_queue_size: get_peak_queue_size()
      },
      errors: %{
        recent_errors: get_recent_job_errors(20),
        error_trends: get_error_trends()
      }
    }

    response_body = Jason.encode!(jobs_data)
    build_http_response(200, response_body, "application/json")
  end

  @doc """
  Provides comprehensive metrics data for dashboard visualization.
  """
  defp handle_dashboard_metrics_api(state) do
    metrics_data = %{
      timestamp: DateTime.utc_now(),
      system_metrics: get_detailed_system_metrics(),
      application_metrics: get_application_metrics(state),
      business_metrics: get_business_metrics(),
      time_series: %{
        cpu_usage: get_cpu_time_series(60),
        memory_usage: get_memory_time_series(60),
        request_rate: get_request_rate_time_series(60),
        error_rate: get_error_rate_time_series(60)
      },
      alerts: get_active_alerts()
    }

    response_body = Jason.encode!(metrics_data)
    build_http_response(200, response_body, "application/json")
  end

  @doc """
  Provides health check data optimized for dashboard display.
  """
  defp handle_dashboard_health_api(state) do
    health_data = %{
      timestamp: DateTime.utc_now(),
      overall_status: get_overall_system_status(state),
      components: get_detailed_component_health(),
      dependencies: get_dependency_health_status(),
      recent_incidents: get_recent_health_incidents(),
      uptime_stats: %{
        current_uptime: get_system_uptime(),
        uptime_percentage_24h: get_uptime_percentage(24),
        uptime_percentage_7d: get_uptime_percentage(168),
        uptime_percentage_30d: get_uptime_percentage(720)
      }
    }

    response_body = Jason.encode!(health_data)
    build_http_response(200, response_body, "application/json")
  end

  @doc """
  Provides system information and resource utilization.
  """
  defp handle_dashboard_system_api(_state) do
    system_data = %{
      timestamp: DateTime.utc_now(),
      host_info: %{
        hostname: :inet.gethostname() |> elem(1) |> to_string(),
        os: get_os_info(),
        architecture: :erlang.system_info(:system_architecture) |> to_string(),
        erlang_version: :erlang.system_info(:otp_release) |> to_string(),
        elixir_version: System.version()
      },
      resources: %{
        memory: get_detailed_memory_info(),
        processes: %{
          count: :erlang.system_info(:process_count),
          limit: :erlang.system_info(:process_limit),
          utilization: :erlang.system_info(:process_count) / :erlang.system_info(:process_limit)
        },
        schedulers: %{
          online: :erlang.system_info(:schedulers_online),
          total: :erlang.system_info(:schedulers)
        }
      },
      network: %{
        node_name: Node.self(),
        connected_nodes: Node.list(),
        distribution_enabled: Node.alive?()
      }
    }

    response_body = Jason.encode!(system_data)
    build_http_response(200, response_body, "application/json")
  end

  @doc """
  Provides recent application logs for dashboard display.
  """
  defp handle_dashboard_logs_api(_state) do
    logs_data = %{
      timestamp: DateTime.utc_now(),
      recent_logs: get_recent_logs(100),
      log_levels: get_log_level_counts(),
      error_summary: get_recent_error_summary()
    }

    response_body = Jason.encode!(logs_data)
    build_http_response(200, response_body, "application/json")
  end

  @doc """
  Provides alert and notification data for dashboard.
  """
  defp handle_dashboard_alerts_api(_state) do
    alerts_data = %{
      timestamp: DateTime.utc_now(),
      active_alerts: get_active_alerts(),
      recent_alerts: get_recent_alerts(50),
      alert_rules: get_configured_alert_rules(),
      alert_statistics: %{
        total_alerts_24h: count_alerts_in_period(24),
        critical_alerts_24h: count_critical_alerts_in_period(24),
        resolved_alerts_24h: count_resolved_alerts_in_period(24)
      }
    }

    response_body = Jason.encode!(alerts_data)
    build_http_response(200, response_body, "application/json")
  end

  @doc """
  Provides streaming metrics endpoint for real-time dashboard updates.
  """
  defp handle_streaming_metrics_endpoint(_state) do
    # Server-Sent Events implementation for real-time metrics
    sse_headers = [
      {"Content-Type", "text/event-stream"},
      {"Cache-Control", "no-cache"},
      {"Connection", "keep-alive"},
      {"Access-Control-Allow-Origin", "*"}
    ]

    # Start streaming process (simplified - would need proper SSE implementation)
    streaming_data =
      "data: " <>
        Jason.encode!(%{
          timestamp: DateTime.utc_now(),
          cpu: get_cpu_usage(),
          memory: get_memory_usage(),
          active_jobs: count_active_jobs()
        }) <> "\n\n"

    build_http_response_with_headers(200, streaming_data, sse_headers)
  end

  @doc """
  Provides streaming logs endpoint for real-time log monitoring.
  """
  defp handle_streaming_logs_endpoint(_state) do
    # Server-Sent Events implementation for real-time logs
    sse_headers = [
      {"Content-Type", "text/event-stream"},
      {"Cache-Control", "no-cache"},
      {"Connection", "keep-alive"},
      {"Access-Control-Allow-Origin", "*"}
    ]

    # Stream recent logs (simplified implementation)
    recent_logs = get_recent_logs(10)

    streaming_data =
      "data: " <>
        Jason.encode!(%{
          timestamp: DateTime.utc_now(),
          logs: recent_logs
        }) <> "\n\n"

    build_http_response_with_headers(200, streaming_data, sse_headers)
  end

  # Administrative Endpoints

  @doc """
  Handles administrative scaling requests.
  """
  defp handle_admin_scale_endpoint(state) do
    # This would parse request body for scaling parameters
    # For now, return current scaling status
    scaling_data = %{
      current_workers: count_active_workers(),
      scaling_available: is_scaling_available(),
      auto_scaling_enabled: is_auto_scaling_enabled()
    }

    response_body = Jason.encode!(scaling_data)
    build_http_response(200, response_body, "application/json")
  end

  @doc """
  Handles administrative restart requests.
  """
  defp handle_admin_restart_endpoint(_state) do
    # This would handle graceful restart requests
    restart_data = %{
      restart_available: true,
      estimated_downtime: "30-60 seconds",
      active_jobs: count_active_jobs()
    }

    response_body = Jason.encode!(restart_data)
    build_http_response(200, response_body, "application/json")
  end

  @doc """
  Handles administrative drain requests.
  """
  defp handle_admin_drain_endpoint(_state) do
    # This would handle drain mode requests
    drain_data = %{
      drain_available: true,
      active_jobs_to_complete: count_active_jobs(),
      estimated_drain_time: calculate_estimated_drain_time()
    }

    response_body = Jason.encode!(drain_data)
    build_http_response(200, response_body, "application/json")
  end

  @doc """
  Handles administrative backup requests.
  """
  defp handle_admin_backup_endpoint(_state) do
    # This would handle backup creation requests
    backup_data = %{
      backup_available: true,
      last_backup: get_last_backup_info(),
      backup_size_estimate: estimate_backup_size()
    }

    response_body = Jason.encode!(backup_data)
    build_http_response(200, response_body, "application/json")
  end

  # Helper functions for enhanced dashboard functionality

  defp generate_dashboard_html do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>LivekitexAgent Dashboard</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
            .container { max-width: 1200px; margin: 0 auto; }
            .header { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
            .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
            .card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
            .metric { display: flex; justify-content: space-between; margin-bottom: 10px; }
            .status-healthy { color: #28a745; }
            .status-warning { color: #ffc107; }
            .status-error { color: #dc3545; }
            .refresh-btn { padding: 10px 20px; background: #007bff; color: white; border: none; border-radius: 4px; cursor: pointer; }
            .refresh-btn:hover { background: #0056b3; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>LivekitexAgent Dashboard</h1>
                <button class="refresh-btn" onclick="refreshDashboard()">Refresh</button>
            </div>

            <div class="grid">
                <div class="card" id="overview-card">
                    <h3>System Overview</h3>
                    <div id="overview-content">Loading...</div>
                </div>

                <div class="card" id="workers-card">
                    <h3>Workers</h3>
                    <div id="workers-content">Loading...</div>
                </div>

                <div class="card" id="jobs-card">
                    <h3>Jobs</h3>
                    <div id="jobs-content">Loading...</div>
                </div>

                <div class="card" id="health-card">
                    <h3>Health Status</h3>
                    <div id="health-content">Loading...</div>
                </div>
            </div>
        </div>

        <script>
            async function loadDashboardData() {
                try {
                    const [overview, workers, jobs, health] = await Promise.all([
                        fetch('/dashboard/api/overview').then(r => r.json()),
                        fetch('/dashboard/api/workers').then(r => r.json()),
                        fetch('/dashboard/api/jobs').then(r => r.json()),
                        fetch('/dashboard/api/health').then(r => r.json())
                    ]);

                    updateOverview(overview);
                    updateWorkers(workers);
                    updateJobs(jobs);
                    updateHealth(health);
                } catch (error) {
                    console.error('Failed to load dashboard data:', error);
                }
            }

            function updateOverview(data) {
                const content = document.getElementById('overview-content');
                content.innerHTML = `
                    <div class="metric"><span>Status:</span><span class="status-${data.system.status.toLowerCase()}">${data.system.status}</span></div>
                    <div class="metric"><span>Uptime:</span><span>${Math.floor(data.uptime / 3600)}h ${Math.floor((data.uptime % 3600) / 60)}m</span></div>
                    <div class="metric"><span>Memory:</span><span>${data.system.memory_usage}%</span></div>
                    <div class="metric"><span>CPU:</span><span>${data.system.cpu_usage}%</span></div>
                `;
            }

            function updateWorkers(data) {
                const content = document.getElementById('workers-content');
                const utilization = Math.round(data.workers.utilization * 100);
                content.innerHTML = `
                    <div class="metric"><span>Active:</span><span>${data.workers.active}/${data.workers.total}</span></div>
                    <div class="metric"><span>Utilization:</span><span>${utilization}%</span></div>
                    <div class="metric"><span>Load Balancer:</span><span>${data.load_balancing.strategy}</span></div>
                    <div class="metric"><span>Auto Scaling:</span><span>${data.scaling.auto_scaling_enabled ? 'Enabled' : 'Disabled'}</span></div>
                `;
            }

            function updateJobs(data) {
                const content = document.getElementById('jobs-content');
                const successRate = Math.round(data.performance.success_rate * 100);
                content.innerHTML = `
                    <div class="metric"><span>Active:</span><span>${data.jobs.active}</span></div>
                    <div class="metric"><span>Pending:</span><span>${data.jobs.pending}</span></div>
                    <div class="metric"><span>Completed Today:</span><span>${data.jobs.completed_today}</span></div>
                    <div class="metric"><span>Success Rate:</span><span>${successRate}%</span></div>
                `;
            }

            function updateHealth(data) {
                const content = document.getElementById('health-content');
                const uptimePercentage = Math.round(data.uptime_stats.uptime_percentage_24h * 100);
                content.innerHTML = `
                    <div class="metric"><span>Overall:</span><span class="status-${data.overall_status.toLowerCase()}">${data.overall_status}</span></div>
                    <div class="metric"><span>Uptime (24h):</span><span>${uptimePercentage}%</span></div>
                    <div class="metric"><span>Components:</span><span>${Object.keys(data.components).length} checked</span></div>
                    <div class="metric"><span>Incidents:</span><span>${data.recent_incidents.length} recent</span></div>
                `;
            }

            function refreshDashboard() {
                loadDashboardData();
            }

            // Load initial data
            loadDashboardData();

            // Auto-refresh every 30 seconds
            setInterval(loadDashboardData, 30000);
        </script>
    </body>
    </html>
    """
  end

  # Data collection helper functions

  defp get_system_uptime do
    try do
      # Try to get system uptime (simplified)
      div(:erlang.monotonic_time() - :erlang.system_info(:start_time), 1_000_000)
    rescue
      _ -> 0
    end
  end

  defp get_overall_system_status(_state) do
    # Simplified system status calculation
    case Process.whereis(LivekitexAgent.WorkerManager) do
      nil -> "ERROR"
      _pid -> "HEALTHY"
    end
  end

  defp get_memory_usage do
    memory = :erlang.memory()
    total = memory[:total]
    system = memory[:system]
    round(system / total * 100)
  end

  defp get_cpu_usage do
    # Simplified CPU usage (would need proper implementation)
    # Mock value between 10-30%
    :rand.uniform(20) + 10
  end

  defp get_load_average do
    # Mock load average (would need proper implementation)
    [:rand.uniform() * 2, :rand.uniform() * 2, :rand.uniform() * 2]
  end

  defp count_active_workers do
    case Process.whereis(LivekitexAgent.WorkerManager) do
      nil ->
        0

      _pid ->
        try do
          status = LivekitexAgent.WorkerManager.get_status()
          status.active_workers_count || 0
        catch
          :exit, _ -> 0
        end
    end
  end

  defp count_total_workers do
    # Would get from worker supervisor or configuration
    # Default value
    4
  end

  defp calculate_worker_utilization do
    active = count_active_workers()
    total = count_total_workers()
    if total > 0, do: active / total, else: 0.0
  end

  defp count_active_jobs do
    case Process.whereis(LivekitexAgent.WorkerManager) do
      nil ->
        0

      _pid ->
        try do
          status = LivekitexAgent.WorkerManager.get_status()
          status.active_jobs_count || 0
        catch
          :exit, _ -> 0
        end
    end
  end

  defp count_pending_jobs do
    case Process.whereis(LivekitexAgent.WorkerManager) do
      nil ->
        0

      _pid ->
        try do
          status = LivekitexAgent.WorkerManager.get_status()
          status.pending_jobs_count || 0
        catch
          :exit, _ -> 0
        end
    end
  end

  defp count_completed_jobs_today do
    # Mock implementation - would need proper metrics storage
    :rand.uniform(100) + 50
  end

  defp calculate_success_rate do
    # Mock implementation - would calculate from real metrics
    # 95-99% success rate
    0.95 + :rand.uniform() * 0.04
  end

  defp get_avg_response_time do
    # Mock implementation
    # 100-600ms
    :rand.uniform(500) + 100
  end

  defp get_requests_per_minute do
    # Mock implementation
    # 20-70 requests per minute
    :rand.uniform(50) + 20
  end

  defp get_error_rate do
    # Mock implementation
    # 0-5% error rate
    :rand.uniform() * 0.05
  end

  defp get_detailed_worker_info do
    # Mock worker information
    []
  end

  defp is_auto_scaling_enabled do
    case Process.whereis(LivekitexAgent.AutoScaler) do
      nil -> false
      _pid -> true
    end
  end

  defp get_min_workers, do: 2
  defp get_max_workers, do: 10
  defp get_scale_up_threshold, do: 0.8
  defp get_scale_down_threshold, do: 0.3

  defp get_load_balancer_strategy do
    # Default strategy
    "round_robin"
  end

  defp get_load_distribution do
    %{balanced: true, variance: 0.1}
  end

  defp get_comprehensive_queue_status do
    %{
      active: count_active_jobs(),
      pending: count_pending_jobs(),
      processing: count_active_jobs(),
      failed: 0
    }
  end

  defp get_recent_job_history(_limit), do: []
  defp get_job_type_statistics, do: %{}
  # ms
  defp get_avg_job_processing_time, do: 1200
  defp get_jobs_per_hour, do: 120
  defp get_peak_queue_size, do: 15
  defp get_recent_job_errors(_limit), do: []
  defp get_error_trends, do: %{increasing: false}

  defp get_detailed_system_metrics do
    %{
      memory: :erlang.memory(),
      processes: :erlang.system_info(:process_count),
      schedulers: :erlang.system_info(:schedulers_online)
    }
  end

  defp get_application_metrics(_state), do: %{}
  defp get_business_metrics, do: %{}
  defp get_cpu_time_series(_minutes), do: []
  defp get_memory_time_series(_minutes), do: []
  defp get_request_rate_time_series(_minutes), do: []
  defp get_error_rate_time_series(_minutes), do: []
  defp get_active_alerts, do: []

  defp get_detailed_component_health, do: %{}
  defp get_dependency_health_status, do: %{}
  defp get_recent_health_incidents, do: []
  defp get_uptime_percentage(_hours), do: 0.99

  defp get_os_info do
    case :os.type() do
      {:unix, type} -> to_string(type)
      {:win32, _} -> "windows"
      _ -> "unknown"
    end
  end

  defp get_detailed_memory_info do
    memory = :erlang.memory()

    %{
      total: memory[:total],
      processes: memory[:processes],
      system: memory[:system],
      atom: memory[:atom],
      binary: memory[:binary],
      ets: memory[:ets]
    }
  end

  defp get_recent_logs(_limit), do: []
  defp get_log_level_counts, do: %{info: 45, warn: 3, error: 1}
  defp get_recent_error_summary, do: %{count: 1, last_error: "Connection timeout"}

  defp get_recent_alerts(_limit), do: []
  defp get_configured_alert_rules, do: []
  defp count_alerts_in_period(_hours), do: 0
  defp count_critical_alerts_in_period(_hours), do: 0
  defp count_resolved_alerts_in_period(_hours), do: 0

  defp is_scaling_available, do: true

  defp calculate_estimated_drain_time do
    active_jobs = count_active_jobs()
    if active_jobs == 0, do: "0 seconds", else: "#{active_jobs * 30} seconds"
  end

  defp get_last_backup_info, do: %{date: "2024-01-01", size: "45MB"}
  defp estimate_backup_size, do: "50MB"

  defp build_http_response_with_headers(status_code, body, headers) do
    status_text =
      case status_code do
        200 -> "OK"
        404 -> "Not Found"
        503 -> "Service Unavailable"
        _ -> "Unknown"
      end

    header_lines = Enum.map(headers, fn {key, value} -> "#{key}: #{value}" end)
    header_string = Enum.join(header_lines, "\r\n")

    """
    HTTP/1.1 #{status_code} #{status_text}\r
    #{header_string}\r
    Content-Length: #{byte_size(body)}\r
    \r
    #{body}
    """
  end

  defp handle_not_found do
    available_endpoints = [
      "/health",
      "/health/ready",
      "/health/live",
      "/metrics",
      "/status",
      "/dashboard",
      "/workers",
      "/jobs",
      "/config",
      "/dashboard/ui",
      "/dashboard/api/overview",
      "/dashboard/api/workers",
      "/dashboard/api/jobs",
      "/dashboard/api/metrics",
      "/dashboard/api/health",
      "/dashboard/api/system",
      "/dashboard/api/logs",
      "/dashboard/api/alerts",
      "/dashboard/streaming/metrics",
      "/dashboard/streaming/logs",
      "/admin/scale",
      "/admin/restart",
      "/admin/drain",
      "/admin/backup"
    ]

    response_body =
      Jason.encode!(%{
        error: "Not Found",
        available_endpoints: available_endpoints
      })

    build_http_response(404, response_body, "application/json")
  end

  defp build_http_response(status_code, body, content_type) do
    status_text =
      case status_code do
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

    results =
      Enum.map(all_checks, fn {name, check_fun} ->
        start_time = System.monotonic_time(:millisecond)

        result =
          try do
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

    # Under 1GB
    if memory_mb < 1000 do
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

    custom_metrics =
      Enum.reduce(state.metrics_collectors, %{}, fn {name, collector_fun}, acc ->
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

  defp get_system_info do
    %{
      node: Node.self(),
      otp_release: :erlang.system_info(:otp_release),
      elixir_version: System.version(),
      schedulers_online: :erlang.system_info(:schedulers_online),
      process_count: :erlang.system_info(:process_count),
      port_count: :erlang.system_info(:port_count),
      memory: %{
        total: :erlang.memory(:total),
        processes: :erlang.memory(:processes),
        system: :erlang.memory(:system),
        atom: :erlang.memory(:atom),
        binary: :erlang.memory(:binary),
        ets: :erlang.memory(:ets)
      },
      system_time: System.system_time(:millisecond)
    }
  end

  defp get_worker_status do
    case Process.whereis(LivekitexAgent.WorkerManager) do
      nil ->
        %{error: "Worker manager not running"}

      _pid ->
        try do
          status = LivekitexAgent.WorkerManager.get_status()
          metrics = LivekitexAgent.WorkerManager.get_metrics()

          %{
            status: status,
            metrics: metrics,
            timestamp: DateTime.utc_now()
          }
        rescue
          e ->
            %{error: "Failed to get worker status", reason: inspect(e)}
        end
    end
  end

  defp get_job_queue_status do
    case Process.whereis(LivekitexAgent.WorkerManager) do
      nil ->
        %{error: "Worker manager not running"}

      _pid ->
        try do
          LivekitexAgent.WorkerManager.get_queue_status()
        rescue
          e ->
            %{error: "Failed to get queue status", reason: inspect(e)}
        end
    end
  end

  defp get_job_status do
    case Process.whereis(LivekitexAgent.WorkerManager) do
      nil ->
        %{error: "Worker manager not running"}

      _pid ->
        try do
          status = LivekitexAgent.WorkerManager.get_status()

          %{
            active_jobs: status.active_jobs_count,
            max_concurrent_jobs: status.max_concurrent_jobs,
            current_load: status.current_load,
            load_threshold: status.load_threshold,
            timestamp: DateTime.utc_now()
          }
        rescue
          e ->
            %{error: "Failed to get job status", reason: inspect(e)}
        end
    end
  end

  defp get_performance_metrics(state) do
    base_metrics = collect_metrics(state)

    %{
      base_metrics: base_metrics,
      cpu_usage: get_cpu_usage(),
      memory_usage: get_memory_usage(),
      network_stats: get_network_stats(),
      gc_stats: get_gc_stats()
    }
  end

  defp get_network_stats do
    %{
      port_count: :erlang.system_info(:port_count),
      # In a real implementation, would get actual network stats
      estimated_connections: length(Port.list())
    }
  end

  defp get_gc_stats do
    # Get garbage collection statistics
    {total_collections, total_words_reclaimed, _} = :erlang.statistics(:garbage_collection)

    %{
      total_collections: total_collections,
      total_words_reclaimed: total_words_reclaimed
    }
  end
end
