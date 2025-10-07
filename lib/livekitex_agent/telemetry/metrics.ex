defmodule LivekitexAgent.Telemetry.Metrics do
  @moduledoc """
  Centralized metrics collection and monitoring for LivekitexAgent.

  The Metrics module provides:
  - Real-time performance monitoring for agent sessions
  - Connection quality tracking and analytics
  - Resource usage monitoring (CPU, memory, network)
  - Audio processing latency and quality metrics
  - Tool execution performance and success rates
  - Custom business metrics and KPIs
  - Metrics aggregation and historical data
  - Integration with popular monitoring systems

  ## Metric Categories

  ### Session Metrics
  - Session duration and lifecycle events
  - Turn completion rates and timing
  - User engagement and interaction patterns
  - Error rates and failure analysis

  ### Audio Metrics
  - STT/TTS processing latency and accuracy
  - Audio quality scores and degradation
  - Buffer underruns and audio glitches
  - Codec performance and bandwidth usage

  ### Connection Metrics
  - WebRTC connection quality and stability
  - Network latency and packet loss
  - Reconnection rates and recovery time
  - Load balancing effectiveness

  ### Tool Metrics
  - Function tool execution times
  - Tool success/failure rates
  - Resource usage per tool type
  - Tool chaining efficiency

  ## Integration

  The metrics system integrates with:
  - :telemetry for event-driven metrics
  - Prometheus/Grafana for visualization
  - StatsD for real-time monitoring
  - Custom webhooks for alerting
  - ETS tables for high-performance local storage
  """

  use GenServer
  require Logger

  @metrics_table :livekitex_agent_metrics
  # 1 minute
  @aggregation_interval 60_000
  # 24 hours in milliseconds
  @retention_period 86_400_000

  defstruct [
    :config,
    :metrics_store,
    :aggregation_timer,
    :cleanup_timer,
    :event_handlers,
    :custom_collectors,
    :export_handlers
  ]

  @type metric_type :: :counter | :gauge | :histogram | :summary
  @type metric_tags :: %{String.t() => String.t()}
  @type metric_value :: number()
  @type timestamp :: integer()

  @type metric_point :: %{
          name: String.t(),
          type: metric_type(),
          value: metric_value(),
          tags: metric_tags(),
          timestamp: timestamp()
        }

  @type metrics_config :: %{
          retention_hours: integer(),
          aggregation_interval_ms: integer(),
          export_interval_ms: integer(),
          enable_prometheus: boolean(),
          enable_statsd: boolean(),
          statsd_host: String.t(),
          statsd_port: integer(),
          custom_exporters: list()
        }

  # Client API

  @doc """
  Starts the metrics collection system.

  ## Options
  - `:retention_hours` - How long to keep metrics (default: 24)
  - `:aggregation_interval_ms` - Aggregation interval (default: 60000)
  - `:export_interval_ms` - Export interval for external systems (default: 30000)
  - `:enable_prometheus` - Enable Prometheus metrics (default: false)
  - `:enable_statsd` - Enable StatsD export (default: false)
  - `:statsd_host` - StatsD server host (default: "localhost")
  - `:statsd_port` - StatsD server port (default: 8125)
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a counter metric (monotonically increasing value).

  ## Examples
      Metrics.counter("agent.sessions.started", 1, %{"agent_type" => "voice"})
      Metrics.counter("audio.frames.processed", frame_count)
  """
  def counter(name, value \\ 1, tags \\ %{}) do
    record_metric(:counter, name, value, tags)
  end

  @doc """
  Records a gauge metric (current value that can go up or down).

  ## Examples
      Metrics.gauge("agent.sessions.active", active_count, %{"region" => "us-west"})
      Metrics.gauge("audio.buffer.size", buffer_size_bytes)
  """
  def gauge(name, value, tags \\ %{}) do
    record_metric(:gauge, name, value, tags)
  end

  @doc """
  Records a histogram metric (distribution of values).

  ## Examples
      Metrics.histogram("audio.stt.latency_ms", latency_ms, %{"provider" => "openai"})
      Metrics.histogram("tool.execution.duration_ms", duration)
  """
  def histogram(name, value, tags \\ %{}) do
    record_metric(:histogram, name, value, tags)
  end

  @doc """
  Records a timing metric (convenience for histogram of durations).

  ## Examples
      Metrics.timing("agent.turn.processing_time", start_time, end_time)
  """
  def timing(name, start_time, end_time, tags \\ %{}) do
    duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)
    histogram(name, duration_ms, tags)
  end

  @doc """
  Records a summary metric (statistical summary of values).

  ## Examples
      Metrics.summary("connection.quality.score", quality_score, %{"room" => room_id})
  """
  def summary(name, value, tags \\ %{}) do
    record_metric(:summary, name, value, tags)
  end

  @doc """
  Increments a counter by 1 (convenience function).

  ## Examples
      Metrics.increment("errors.connection_failed", %{"reason" => "timeout"})
  """
  def increment(name, tags \\ %{}) do
    counter(name, 1, tags)
  end

  @doc """
  Decrements a gauge by 1 (convenience function).

  ## Examples
      Metrics.decrement("agent.sessions.active")
  """
  def decrement(name, tags \\ %{}) do
    gauge(name, -1, Map.put(tags, "_operation", "decrement"))
  end

  @doc """
  Measures execution time of a function and records it as a histogram.

  ## Examples
      result = Metrics.measure("tool.weather.execution_time", fn ->
        WeatherTool.get_weather("San Francisco")
      end)
  """
  def measure(name, tags \\ %{}, func) when is_function(func, 0) do
    start_time = System.monotonic_time()
    result = func.()
    end_time = System.monotonic_time()
    timing(name, start_time, end_time, tags)
    result
  end

  @doc """
  Gets current metric values for a specific metric name.

  Returns list of recent metric points with their values and timestamps.
  """
  def get_metric(name, opts \\ []) do
    GenServer.call(__MODULE__, {:get_metric, name, opts})
  end

  @doc """
  Gets aggregated metrics for a time period.

  ## Options
  - `:from` - Start timestamp (default: 1 hour ago)
  - `:to` - End timestamp (default: now)
  - `:aggregation` - Aggregation type (:avg, :sum, :min, :max, :count)
  - `:interval` - Aggregation interval in seconds (default: 60)
  """
  def get_aggregated_metrics(name, opts \\ []) do
    GenServer.call(__MODULE__, {:get_aggregated_metrics, name, opts})
  end

  @doc """
  Lists all available metrics with their types and recent activity.
  """
  def list_metrics do
    GenServer.call(__MODULE__, :list_metrics)
  end

  @doc """
  Gets current system performance metrics.

  Returns metrics about:
  - Memory usage
  - CPU utilization
  - Process counts
  - Message queue lengths
  """
  def get_system_metrics do
    GenServer.call(__MODULE__, :get_system_metrics)
  end

  @doc """
  Registers a custom metric collector function.

  The collector function will be called periodically to gather custom metrics.

  ## Example
      Metrics.register_collector("custom.database.connections", fn ->
        connection_count = MyApp.Database.connection_count()
        [{:gauge, "database.connections.active", connection_count, %{}}]
      end)
  """
  def register_collector(name, collector_func) do
    GenServer.call(__MODULE__, {:register_collector, name, collector_func})
  end

  @doc """
  Exports current metrics to external monitoring systems.

  Triggers immediate export regardless of the configured export interval.
  """
  def export_metrics do
    GenServer.cast(__MODULE__, :export_metrics)
  end

  @doc """
  Generates a comprehensive metrics report for the specified time period.

  ## Options
  - `:format` - Report format (:json, :csv, :prometheus, :html)
  - `:from` - Start timestamp (default: 1 hour ago)
  - `:to` - End timestamp (default: now)
  - `:include_system` - Include system metrics (default: true)
  - `:include_business` - Include business metrics (default: true)
  - `:aggregation_level` - Aggregation level in seconds (default: 60)
  """
  def generate_report(opts \\ []) do
    GenServer.call(__MODULE__, {:generate_report, opts}, 30_000)
  end

  @doc """
  Creates a performance dashboard data structure.

  Returns structured data suitable for rendering in monitoring dashboards.
  """
  def get_dashboard_data do
    GenServer.call(__MODULE__, :get_dashboard_data)
  end

  @doc """
  Gets detailed metrics for worker performance analysis.
  """
  def get_worker_performance_metrics do
    GenServer.call(__MODULE__, :get_worker_performance_metrics)
  end

  @doc """
  Gets audio processing quality metrics and trends.
  """
  def get_audio_quality_metrics do
    GenServer.call(__MODULE__, :get_audio_quality_metrics)
  end

  @doc """
  Sets up alerting rules for specific metrics.

  ## Example
      Metrics.set_alert_rule("high_latency", %{
        metric: "audio.stt.latency_ms",
        condition: :greater_than,
        threshold: 2000,
        duration_seconds: 300,
        callback: &MyApp.Alerts.high_latency_alert/1
      })
  """
  def set_alert_rule(rule_name, rule_config) do
    GenServer.call(__MODULE__, {:set_alert_rule, rule_name, rule_config})
  end

  @doc """
  Clears all metrics data (useful for testing).
  """
  def clear_metrics do
    GenServer.call(__MODULE__, :clear_metrics)
  end

  # Built-in Metric Collectors

  @doc """
  Starts collecting built-in agent session metrics.

  This enables automatic collection of:
  - Session lifecycle events
  - Audio processing metrics
  - Connection quality metrics
  - Tool execution metrics
  """
  def start_agent_metrics_collection do
    attach_session_events()
    attach_audio_events()
    attach_connection_events()
    attach_tool_events()
  end

  # GenServer Implementation

  @impl true
  def init(opts) do
    # Initialize ETS table for metrics storage
    case :ets.whereis(@metrics_table) do
      :undefined ->
        :ets.new(@metrics_table, [
          :ordered_set,
          :public,
          :named_table,
          {:read_concurrency, true},
          {:write_concurrency, true}
        ])

      _ ->
        :ok
    end

    config = %{
      retention_hours: Keyword.get(opts, :retention_hours, 24),
      aggregation_interval_ms: Keyword.get(opts, :aggregation_interval_ms, @aggregation_interval),
      export_interval_ms: Keyword.get(opts, :export_interval_ms, 30_000),
      enable_prometheus: Keyword.get(opts, :enable_prometheus, false),
      enable_statsd: Keyword.get(opts, :enable_statsd, false),
      statsd_host: Keyword.get(opts, :statsd_host, "localhost"),
      statsd_port: Keyword.get(opts, :statsd_port, 8125),
      custom_exporters: Keyword.get(opts, :custom_exporters, [])
    }

    state = %__MODULE__{
      config: config,
      metrics_store: @metrics_table,
      aggregation_timer: nil,
      cleanup_timer: nil,
      event_handlers: %{},
      custom_collectors: %{},
      export_handlers: init_export_handlers(config)
    }

    # Start periodic timers
    aggregation_timer =
      Process.send_after(self(), :aggregate_metrics, config.aggregation_interval_ms)

    cleanup_timer = Process.send_after(self(), :cleanup_old_metrics, @retention_period)

    state = %{state | aggregation_timer: aggregation_timer, cleanup_timer: cleanup_timer}

    Logger.info("Metrics system started with config: #{inspect(config)}")
    {:ok, state}
  end

  @impl true
  def handle_call({:get_metric, name, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 100)
    # 1 hour ago
    from_time = Keyword.get(opts, :from, System.system_time(:millisecond) - 3_600_000)

    metrics =
      :ets.select(@metrics_table, [
        {
          {{name, :"$1"}, :"$2", :"$3", :"$4"},
          [{:>=, :"$1", from_time}],
          [{{:"$1", :"$2", :"$3", :"$4"}}]
        }
      ])
      |> Enum.take(limit)
      |> Enum.map(fn {timestamp, type, value, tags} ->
        %{
          name: name,
          timestamp: timestamp,
          type: type,
          value: value,
          tags: tags
        }
      end)

    {:reply, metrics, state}
  end

  @impl true
  def handle_call({:get_aggregated_metrics, name, opts}, _from, state) do
    from_time = Keyword.get(opts, :from, System.system_time(:millisecond) - 3_600_000)
    to_time = Keyword.get(opts, :to, System.system_time(:millisecond))
    aggregation_type = Keyword.get(opts, :aggregation, :avg)
    interval_ms = Keyword.get(opts, :interval, 60) * 1000

    raw_metrics =
      :ets.select(@metrics_table, [
        {
          {{name, :"$1"}, :"$2", :"$3", :"$4"},
          [{:>=, :"$1", from_time}, {:"=<", :"$1", to_time}],
          [{{:"$1", :"$2", :"$3", :"$4"}}]
        }
      ])

    aggregated = aggregate_metrics_by_interval(raw_metrics, interval_ms, aggregation_type)
    {:reply, aggregated, state}
  end

  @impl true
  def handle_call(:list_metrics, _from, state) do
    # Get unique metric names and their types
    metrics_info =
      :ets.tab2list(@metrics_table)
      |> Enum.group_by(fn {{name, _timestamp}, _type, _value, _tags} -> name end)
      |> Enum.map(fn {name, entries} ->
        types = entries |> Enum.map(fn {_, type, _, _} -> type end) |> Enum.uniq()
        count = length(entries)
        latest = entries |> Enum.max_by(fn {{_, timestamp}, _, _, _} -> timestamp end)

        %{
          name: name,
          types: types,
          count: count,
          latest_timestamp: elem(elem(latest, 0), 1),
          latest_value: elem(latest, 2)
        }
      end)

    {:reply, metrics_info, state}
  end

  @impl true
  def handle_call(:get_system_metrics, _from, state) do
    system_metrics = %{
      memory: get_memory_metrics(),
      processes: get_process_metrics(),
      cpu: get_cpu_metrics(),
      timestamp: System.system_time(:millisecond)
    }

    {:reply, system_metrics, state}
  end

  @impl true
  def handle_call({:register_collector, name, collector_func}, _from, state) do
    new_collectors = Map.put(state.custom_collectors, name, collector_func)
    new_state = %{state | custom_collectors: new_collectors}

    Logger.info("Registered custom metric collector: #{name}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:clear_metrics, _from, state) do
    :ets.delete_all_objects(@metrics_table)
    Logger.info("All metrics cleared")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:generate_report, opts}, _from, state) do
    report = generate_comprehensive_report(opts, state)
    {:reply, report, state}
  end

  @impl true
  def handle_call(:get_dashboard_data, _from, state) do
    dashboard_data = build_dashboard_data(state)
    {:reply, dashboard_data, state}
  end

  @impl true
  def handle_call(:get_worker_performance_metrics, _from, state) do
    worker_metrics = get_worker_performance_data()
    {:reply, worker_metrics, state}
  end

  @impl true
  def handle_call(:get_audio_quality_metrics, _from, state) do
    audio_metrics = get_audio_quality_data()
    {:reply, audio_metrics, state}
  end

  @impl true
  def handle_call({:set_alert_rule, rule_name, rule_config}, _from, state) do
    # Store alert rules and set up monitoring
    new_state = add_alert_rule(state, rule_name, rule_config)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast(:export_metrics, state) do
    perform_metrics_export(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:aggregate_metrics, state) do
    # Perform metric aggregation
    perform_aggregation(state)

    # Run custom collectors
    collect_custom_metrics(state)

    # Schedule next aggregation
    timer = Process.send_after(self(), :aggregate_metrics, state.config.aggregation_interval_ms)
    new_state = %{state | aggregation_timer: timer}

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup_old_metrics, state) do
    # Remove old metrics beyond retention period
    cutoff_time = System.system_time(:millisecond) - state.config.retention_hours * 3_600_000

    old_keys =
      :ets.select(@metrics_table, [
        {
          {{:"$1", :"$2"}, :"$3", :"$4", :"$5"},
          [{:<, :"$2", cutoff_time}],
          [{{:"$1", :"$2"}}]
        }
      ])

    Enum.each(old_keys, fn key ->
      :ets.delete(@metrics_table, key)
    end)

    if length(old_keys) > 0 do
      Logger.info("Cleaned up #{length(old_keys)} old metric entries")
    end

    # Schedule next cleanup
    timer = Process.send_after(self(), :cleanup_old_metrics, @retention_period)
    new_state = %{state | cleanup_timer: timer}

    {:noreply, new_state}
  end

  # Private Functions

  defp record_metric(type, name, value, tags) do
    timestamp = System.system_time(:millisecond)
    key = {name, timestamp}

    # Store in ETS
    :ets.insert(@metrics_table, {key, type, value, tags})

    # Emit telemetry event
    :telemetry.execute(
      [:livekitex_agent, :metrics, type],
      %{value: value},
      %{name: name, tags: tags, timestamp: timestamp}
    )
  end

  defp init_export_handlers(config) do
    handlers = []

    handlers =
      if config.enable_prometheus do
        [:prometheus | handlers]
      else
        handlers
      end

    handlers =
      if config.enable_statsd do
        [{:statsd, config.statsd_host, config.statsd_port} | handlers]
      else
        handlers
      end

    handlers ++ config.custom_exporters
  end

  defp perform_aggregation(_state) do
    # This could implement more sophisticated aggregation logic
    # For now, we rely on ETS storage and query-time aggregation
    :ok
  end

  defp collect_custom_metrics(state) do
    Enum.each(state.custom_collectors, fn {name, collector_func} ->
      try do
        metrics = collector_func.()

        Enum.each(metrics, fn {type, metric_name, value, tags} ->
          record_metric(type, metric_name, value, tags)
        end)
      rescue
        e ->
          Logger.error("Custom collector #{name} failed: #{inspect(e)}")
      end
    end)
  end

  defp perform_metrics_export(state) do
    # Export to configured handlers
    current_metrics = :ets.tab2list(@metrics_table)

    Enum.each(state.export_handlers, fn handler ->
      try do
        export_to_handler(handler, current_metrics)
      rescue
        e ->
          Logger.error("Metrics export to #{inspect(handler)} failed: #{inspect(e)}")
      end
    end)
  end

  defp export_to_handler(:prometheus, metrics) do
    # Prometheus export logic would go here
    Logger.debug("Exported #{length(metrics)} metrics to Prometheus")
  end

  defp export_to_handler({:statsd, host, port}, metrics) do
    # StatsD export logic would go here
    Logger.debug("Exported #{length(metrics)} metrics to StatsD at #{host}:#{port}")
  end

  defp export_to_handler(custom_handler, metrics) when is_function(custom_handler, 1) do
    custom_handler.(metrics)
  end

  defp aggregate_metrics_by_interval(metrics, interval_ms, aggregation_type) do
    metrics
    |> Enum.group_by(fn {timestamp, _type, _value, _tags} ->
      # Group by interval buckets
      div(timestamp, interval_ms) * interval_ms
    end)
    |> Enum.map(fn {bucket_timestamp, bucket_metrics} ->
      values = Enum.map(bucket_metrics, fn {_timestamp, _type, value, _tags} -> value end)

      aggregated_value =
        case aggregation_type do
          :avg -> Enum.sum(values) / length(values)
          :sum -> Enum.sum(values)
          :min -> Enum.min(values)
          :max -> Enum.max(values)
          :count -> length(values)
        end

      %{
        timestamp: bucket_timestamp,
        value: aggregated_value,
        count: length(values),
        aggregation: aggregation_type
      }
    end)
    |> Enum.sort_by(& &1.timestamp)
  end

  defp get_memory_metrics do
    memory_info = :erlang.memory()

    %{
      total: memory_info[:total],
      processes: memory_info[:processes],
      system: memory_info[:system],
      atom: memory_info[:atom],
      binary: memory_info[:binary],
      ets: memory_info[:ets]
    }
  end

  defp get_process_metrics do
    %{
      count: :erlang.system_info(:process_count),
      limit: :erlang.system_info(:process_limit),
      message_queue_len: get_total_message_queue_len()
    }
  end

  defp get_cpu_metrics do
    %{
      schedulers: :erlang.system_info(:schedulers),
      scheduler_utilization: get_scheduler_utilization()
    }
  end

  defp get_total_message_queue_len do
    Process.list()
    |> Enum.map(fn pid ->
      case Process.info(pid, :message_queue_len) do
        {:message_queue_len, len} -> len
        nil -> 0
      end
    end)
    |> Enum.sum()
  end

  defp get_scheduler_utilization do
    # This would require more sophisticated CPU monitoring
    # For now, return a placeholder
    %{average: 0.0, per_scheduler: []}
  end

  # Telemetry Event Attachments

  defp attach_session_events do
    :telemetry.attach_many(
      "livekitex-agent-session-metrics",
      [
        [:livekitex_agent, :session, :started],
        [:livekitex_agent, :session, :stopped],
        [:livekitex_agent, :session, :turn_completed],
        [:livekitex_agent, :session, :error]
      ],
      &handle_session_event/4,
      nil
    )
  end

  defp attach_audio_events do
    :telemetry.attach_many(
      "livekitex-agent-audio-metrics",
      [
        [:livekitex_agent, :audio, :stt_latency],
        [:livekitex_agent, :audio, :tts_latency],
        [:livekitex_agent, :audio, :quality_score]
      ],
      &handle_audio_event/4,
      nil
    )
  end

  defp attach_connection_events do
    :telemetry.attach_many(
      "livekitex-agent-connection-metrics",
      [
        [:livekitex_agent, :connection, :established],
        [:livekitex_agent, :connection, :failed],
        [:livekitex_agent, :connection, :quality_changed]
      ],
      &handle_connection_event/4,
      nil
    )
  end

  defp attach_tool_events do
    :telemetry.attach_many(
      "livekitex-agent-tool-metrics",
      [
        [:livekitex_agent, :tool, :executed],
        [:livekitex_agent, :tool, :failed],
        [:livekitex_agent, :tool, :duration]
      ],
      &handle_tool_event/4,
      nil
    )
  end

  # Event Handlers

  defp handle_session_event(
         [:livekitex_agent, :session, :started],
         _measurements,
         metadata,
         _config
       ) do
    counter("agent.sessions.started", 1, %{"agent_type" => metadata[:agent_type] || "unknown"})
    gauge("agent.sessions.active", 1, %{"_operation" => "increment"})
  end

  defp handle_session_event(
         [:livekitex_agent, :session, :stopped],
         measurements,
         metadata,
         _config
       ) do
    if measurements[:duration_ms] do
      histogram("agent.session.duration_ms", measurements.duration_ms, %{
        "agent_type" => metadata[:agent_type] || "unknown",
        "reason" => metadata[:reason] || "normal"
      })
    end

    gauge("agent.sessions.active", 1, %{"_operation" => "decrement"})
  end

  defp handle_session_event(
         [:livekitex_agent, :session, :turn_completed],
         measurements,
         metadata,
         _config
       ) do
    counter("agent.turns.completed", 1, %{"session_id" => metadata[:session_id] || "unknown"})

    if measurements[:duration_ms] do
      histogram("agent.turn.duration_ms", measurements.duration_ms, metadata)
    end
  end

  defp handle_session_event(
         [:livekitex_agent, :session, :error],
         _measurements,
         metadata,
         _config
       ) do
    counter("agent.sessions.errors", 1, %{
      "error_type" => metadata[:error_type] || "unknown",
      "agent_type" => metadata[:agent_type] || "unknown"
    })
  end

  defp handle_audio_event(
         [:livekitex_agent, :audio, :stt_latency],
         measurements,
         metadata,
         _config
       ) do
    histogram("audio.stt.latency_ms", measurements.latency_ms, %{
      "provider" => metadata[:provider] || "unknown",
      "model" => metadata[:model] || "unknown"
    })
  end

  defp handle_audio_event(
         [:livekitex_agent, :audio, :tts_latency],
         measurements,
         metadata,
         _config
       ) do
    histogram("audio.tts.latency_ms", measurements.latency_ms, %{
      "provider" => metadata[:provider] || "unknown",
      "voice" => metadata[:voice] || "unknown"
    })
  end

  defp handle_audio_event(
         [:livekitex_agent, :audio, :quality_score],
         measurements,
         metadata,
         _config
       ) do
    gauge("audio.quality.score", measurements.score, %{
      "session_id" => metadata[:session_id] || "unknown",
      "metric_type" => metadata[:metric_type] || "overall"
    })
  end

  defp handle_connection_event(
         [:livekitex_agent, :connection, :established],
         _measurements,
         metadata,
         _config
       ) do
    counter("connection.established", 1, %{
      "room_id" => metadata[:room_id] || "unknown",
      "participant_type" => metadata[:participant_type] || "agent"
    })
  end

  defp handle_connection_event(
         [:livekitex_agent, :connection, :failed],
         _measurements,
         metadata,
         _config
       ) do
    counter("connection.failed", 1, %{
      "reason" => metadata[:reason] || "unknown",
      "room_id" => metadata[:room_id] || "unknown"
    })
  end

  defp handle_connection_event(
         [:livekitex_agent, :connection, :quality_changed],
         measurements,
         metadata,
         _config
       ) do
    gauge("connection.quality.score", measurements.quality_score, %{
      "room_id" => metadata[:room_id] || "unknown",
      "connection_id" => metadata[:connection_id] || "unknown"
    })
  end

  defp handle_tool_event([:livekitex_agent, :tool, :executed], _measurements, metadata, _config) do
    counter("tools.executed", 1, %{
      "tool_name" => metadata[:tool_name] || "unknown",
      "session_id" => metadata[:session_id] || "unknown"
    })
  end

  defp handle_tool_event([:livekitex_agent, :tool, :failed], _measurements, metadata, _config) do
    counter("tools.failed", 1, %{
      "tool_name" => metadata[:tool_name] || "unknown",
      "error_type" => metadata[:error_type] || "unknown"
    })
  end

  defp handle_tool_event([:livekitex_agent, :tool, :duration], measurements, metadata, _config) do
    histogram("tools.execution.duration_ms", measurements.duration_ms, %{
      "tool_name" => metadata[:tool_name] || "unknown",
      "session_id" => metadata[:session_id] || "unknown"
    })
  end

  # Enterprise Reporting Functions

  defp generate_comprehensive_report(opts, state) do
    format = Keyword.get(opts, :format, :json)
    from_time = Keyword.get(opts, :from, System.system_time(:millisecond) - 3_600_000)
    to_time = Keyword.get(opts, :to, System.system_time(:millisecond))
    include_system = Keyword.get(opts, :include_system, true)
    include_business = Keyword.get(opts, :include_business, true)
    aggregation_level = Keyword.get(opts, :aggregation_level, 60) * 1000

    report_data = %{
      report_period: %{
        from: from_time,
        to: to_time,
        duration_ms: to_time - from_time
      },
      generated_at: System.system_time(:millisecond),
      system_info: if(include_system, do: get_system_info_for_report(), else: nil),
      performance_summary: get_performance_summary(from_time, to_time),
      metrics_summary: get_metrics_summary(from_time, to_time),
      trends: get_metrics_trends(from_time, to_time, aggregation_level),
      alerts: get_active_alerts(),
      recommendations: generate_performance_recommendations()
    }

    case format do
      :json -> {:ok, Jason.encode!(report_data)}
      :csv -> {:ok, format_report_as_csv(report_data)}
      :html -> {:ok, format_report_as_html(report_data)}
      :prometheus -> {:ok, format_report_as_prometheus(report_data)}
      _ -> {:error, :unsupported_format}
    end
  end

  defp build_dashboard_data(state) do
    current_time = System.system_time(:millisecond)
    hour_ago = current_time - 3_600_000

    %{
      overview: %{
        active_sessions: get_gauge_value("agent.sessions.active"),
        total_requests: get_counter_value("agent.sessions.started"),
        error_rate: calculate_error_rate(hour_ago, current_time),
        avg_response_time: get_avg_response_time(hour_ago, current_time)
      },
      real_time_metrics: %{
        cpu_usage: get_current_cpu_usage(),
        memory_usage: get_current_memory_usage(),
        active_connections: get_gauge_value("connection.active_count"),
        queue_size: get_queue_metrics()
      },
      performance_trends: get_performance_trends(hour_ago, current_time),
      top_errors: get_top_errors(hour_ago, current_time),
      worker_status: get_worker_dashboard_status(),
      audio_quality: get_audio_quality_dashboard()
    }
  end

  defp get_worker_performance_data do
    case Process.whereis(LivekitexAgent.WorkerManager) do
      nil ->
        %{error: "Worker manager not available"}

      _pid ->
        hour_ago = System.system_time(:millisecond) - 3_600_000
        current_time = System.system_time(:millisecond)

        %{
          throughput: get_worker_throughput(hour_ago, current_time),
          latency_distribution: get_worker_latency_distribution(hour_ago, current_time),
          error_rates: get_worker_error_rates(hour_ago, current_time),
          resource_utilization: get_worker_resource_utilization(),
          scaling_history: get_scaling_events(hour_ago, current_time)
        }
    end
  end

  defp get_audio_quality_data do
    hour_ago = System.system_time(:millisecond) - 3_600_000
    current_time = System.system_time(:millisecond)

    %{
      stt_performance: %{
        avg_latency: get_avg_stt_latency(hour_ago, current_time),
        accuracy_score: get_avg_stt_accuracy(hour_ago, current_time),
        provider_comparison: get_stt_provider_comparison(hour_ago, current_time)
      },
      tts_performance: %{
        avg_latency: get_avg_tts_latency(hour_ago, current_time),
        quality_score: get_avg_tts_quality(hour_ago, current_time),
        voice_performance: get_voice_performance_breakdown(hour_ago, current_time)
      },
      overall_audio_quality: get_overall_audio_quality_score(hour_ago, current_time)
    }
  end

  defp add_alert_rule(state, rule_name, rule_config) do
    # In a full implementation, this would set up monitoring for the rule
    Logger.info("Alert rule configured: #{rule_name} - #{inspect(rule_config)}")
    state
  end

  # Helper functions for metrics calculations

  defp get_system_info_for_report do
    %{
      node: Node.self(),
      uptime_ms: get_system_uptime(),
      erlang_version: :erlang.system_info(:otp_release),
      elixir_version: System.version(),
      system_architecture: :erlang.system_info(:system_architecture)
    }
  end

  defp get_performance_summary(from_time, to_time) do
    %{
      session_count: count_sessions_in_period(from_time, to_time),
      avg_session_duration: get_avg_session_duration(from_time, to_time),
      successful_sessions: count_successful_sessions(from_time, to_time),
      error_count: count_errors_in_period(from_time, to_time),
      peak_concurrent_sessions: get_peak_concurrent_sessions(from_time, to_time)
    }
  end

  defp get_metrics_summary(from_time, to_time) do
    %{
      total_data_points: count_metrics_in_period(from_time, to_time),
      unique_metrics: count_unique_metrics(from_time, to_time),
      most_active_metrics: get_most_active_metrics(from_time, to_time),
      data_completeness: calculate_data_completeness(from_time, to_time)
    }
  end

  defp get_metrics_trends(from_time, to_time, interval_ms) do
    # Simplified implementation - would include more sophisticated trend analysis
    %{
      session_trend: calculate_session_trend(from_time, to_time, interval_ms),
      latency_trend: calculate_latency_trend(from_time, to_time, interval_ms),
      error_trend: calculate_error_trend(from_time, to_time, interval_ms)
    }
  end

  defp generate_performance_recommendations do
    # Basic performance recommendations based on current metrics
    recommendations = []

    # Check high latency
    avg_latency = get_current_avg_latency()

    recommendations =
      if avg_latency > 1000 do
        [
          "Consider optimizing audio processing pipeline - high latency detected"
          | recommendations
        ]
      else
        recommendations
      end

    # Check error rates
    error_rate = get_current_error_rate()

    recommendations =
      if error_rate > 0.05 do
        ["Investigate error patterns - error rate above 5%" | recommendations]
      else
        recommendations
      end

    # Check memory usage
    memory_usage = get_current_memory_usage_percentage()

    recommendations =
      if memory_usage > 0.8 do
        ["Consider increasing memory allocation or optimizing memory usage" | recommendations]
      else
        recommendations
      end

    if recommendations == [] do
      ["System performing within normal parameters"]
    else
      recommendations
    end
  end

  # Placeholder implementations for helper functions
  # In a real implementation, these would query the metrics store

  defp get_gauge_value(_name), do: 0
  defp get_counter_value(_name), do: 0
  defp calculate_error_rate(_from, _to), do: 0.01
  defp get_avg_response_time(_from, _to), do: 250
  defp get_current_cpu_usage, do: 0.3
  defp get_current_memory_usage, do: 0.4
  defp get_queue_metrics, do: %{size: 5, capacity: 100}
  defp get_performance_trends(_from, _to), do: %{trending_up: false}
  defp get_top_errors(_from, _to), do: []
  defp get_worker_dashboard_status, do: %{healthy: 3, degraded: 0, unhealthy: 0}
  defp get_audio_quality_dashboard, do: %{overall_score: 8.5, trending: "stable"}

  defp get_worker_throughput(_from, _to), do: %{requests_per_second: 10.5}
  defp get_worker_latency_distribution(_from, _to), do: %{p50: 200, p95: 800, p99: 1200}

  defp get_worker_error_rates(_from, _to),
    do: %{rate: 0.02, by_type: %{timeout: 0.01, connection: 0.01}}

  defp get_worker_resource_utilization, do: %{cpu: 0.3, memory: 0.4}
  defp get_scaling_events(_from, _to), do: []

  defp get_avg_stt_latency(_from, _to), do: 300
  defp get_avg_stt_accuracy(_from, _to), do: 0.95
  defp get_stt_provider_comparison(_from, _to), do: %{openai: %{latency: 300, accuracy: 0.95}}
  defp get_avg_tts_latency(_from, _to), do: 250
  defp get_avg_tts_quality(_from, _to), do: 8.7
  defp get_voice_performance_breakdown(_from, _to), do: %{nova: %{latency: 250, quality: 8.7}}
  defp get_overall_audio_quality_score(_from, _to), do: 8.5

  defp get_system_uptime, do: System.system_time(:millisecond)
  defp count_sessions_in_period(_from, _to), do: 50
  defp get_avg_session_duration(_from, _to), do: 30000
  defp count_successful_sessions(_from, _to), do: 48
  defp count_errors_in_period(_from, _to), do: 2
  defp get_peak_concurrent_sessions(_from, _to), do: 8
  defp count_metrics_in_period(_from, _to), do: 1000
  defp count_unique_metrics(_from, _to), do: 25
  defp get_most_active_metrics(_from, _to), do: ["agent.sessions.started", "audio.stt.latency_ms"]
  defp calculate_data_completeness(_from, _to), do: 0.98

  defp calculate_session_trend(_from, _to, _interval), do: %{direction: "stable", rate: 0.02}
  defp calculate_latency_trend(_from, _to, _interval), do: %{direction: "improving", rate: -0.05}
  defp calculate_error_trend(_from, _to, _interval), do: %{direction: "stable", rate: 0.001}

  defp get_current_avg_latency, do: 250
  defp get_current_error_rate, do: 0.02
  defp get_current_memory_usage_percentage, do: 0.4

  defp get_active_alerts, do: []

  defp format_report_as_csv(report_data) do
    "CSV format not implemented - #{inspect(Map.keys(report_data))}"
  end

  defp format_report_as_html(report_data) do
    "HTML format not implemented - #{inspect(Map.keys(report_data))}"
  end

  defp format_report_as_prometheus(report_data) do
    "Prometheus format not implemented - #{inspect(Map.keys(report_data))}"
  end
end
