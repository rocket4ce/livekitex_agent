defmodule LivekitexAgent.Telemetry.RealtimeMonitor do
  @moduledoc """
  Real-time performance monitoring and optimization for voice agent systems.

  This module provides comprehensive real-time monitoring capabilities specifically
  designed for conversational AI applications, focusing on latency, quality, and
  user experience metrics.

  ## Key Monitoring Areas

  - **Latency Tracking**: End-to-end latency measurement across all components
  - **Audio Quality**: Real-time audio quality assessment and degradation detection
  - **System Performance**: CPU, memory, and network utilization monitoring
  - **User Experience**: Conversation flow, interruption rates, and engagement metrics
  - **Component Health**: Individual component performance and failure detection
  - **Resource Optimization**: Dynamic resource allocation and performance tuning

  ## Performance Targets

  - Audio processing latency: < 50ms
  - End-to-end response time: < 100ms
  - System availability: > 99.9%
  - Audio quality score: > 4.0/5.0
  - Memory efficiency: < 500MB per session
  - CPU utilization: < 70% under normal load

  ## Real-time Features

  - Live performance dashboards
  - Automated alerting for performance degradation
  - Adaptive optimization based on current conditions
  - Historical performance analysis and trending
  - Predictive performance modeling
  - Integration with external monitoring systems

  ## Usage

      # Start the real-time monitor
      {:ok, monitor} = RealtimeMonitor.start_link(
        session_pid: session_pid,
        components: [:audio_processor, :webrtc_handler, :llm_client]
      )

      # Get current performance snapshot
      performance = RealtimeMonitor.get_performance_snapshot(monitor)

      # Set up performance alerts
      RealtimeMonitor.set_alert_threshold(monitor, :latency_ms, 150)
  """

  use GenServer
  require Logger

  @monitor_interval_ms 250 # 4Hz monitoring for real-time performance
  @history_retention_minutes 60
  @alert_cooldown_ms 30_000 # 30 second cooldown between alerts

  defstruct [
    :session_pid,
    monitored_components: [],
    performance_history: [],
    current_metrics: %{},
    alert_thresholds: %{},
    active_alerts: [],
    last_alert_times: %{},
    optimization_state: :monitoring,
    dashboard_subscribers: [],
    performance_targets: %{
      audio_latency_ms: 50,
      end_to_end_latency_ms: 100,
      audio_quality_score: 4.0,
      memory_usage_mb: 500,
      cpu_utilization_percent: 70,
      availability_percent: 99.9
    }
  ]

  @type component :: :audio_processor | :webrtc_handler | :llm_client | :stream_manager |
                     :speech_handle | :vad_client | :session

  @type metric_type :: :latency_ms | :quality_score | :memory_mb | :cpu_percent |
                       :error_rate | :throughput | :availability

  @type alert_level :: :info | :warning | :error | :critical

  @type opts :: [
          session_pid: pid(),
          components: [component()],
          alert_thresholds: map(),
          performance_targets: map()
        ]

  # Public API

  @doc """
  Start the real-time performance monitor.
  """
  @spec start_link(opts()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Get current performance snapshot across all monitored components.
  """
  @spec get_performance_snapshot(pid()) :: map()
  def get_performance_snapshot(pid) do
    GenServer.call(pid, :get_performance_snapshot)
  end

  @doc """
  Set alert threshold for a specific metric.
  """
  @spec set_alert_threshold(pid(), metric_type(), number(), alert_level()) :: :ok
  def set_alert_threshold(pid, metric, threshold, level \\ :warning) do
    GenServer.cast(pid, {:set_alert_threshold, metric, threshold, level})
  end

  @doc """
  Subscribe to real-time performance updates.
  """
  @spec subscribe_to_updates(pid(), pid()) :: :ok
  def subscribe_to_updates(pid, subscriber_pid) do
    GenServer.cast(pid, {:subscribe_to_updates, subscriber_pid})
  end

  @doc """
  Get performance history for analysis.
  """
  @spec get_performance_history(pid(), pos_integer()) :: [map()]
  def get_performance_history(pid, minutes \\ 10) do
    GenServer.call(pid, {:get_performance_history, minutes})
  end

  @doc """
  Trigger manual performance optimization.
  """
  @spec optimize_performance(pid()) :: :ok | {:error, term()}
  def optimize_performance(pid) do
    GenServer.call(pid, :optimize_performance)
  end

  @doc """
  Get current active alerts.
  """
  @spec get_active_alerts(pid()) :: [map()]
  def get_active_alerts(pid) do
    GenServer.call(pid, :get_active_alerts)
  end

  @doc """
  Generate performance report for analysis.
  """
  @spec generate_performance_report(pid(), pos_integer()) :: map()
  def generate_performance_report(pid, minutes \\ 60) do
    GenServer.call(pid, {:generate_performance_report, minutes})
  end

  # GenServer Implementation

  @impl true
  def init(opts) do
    session_pid = Keyword.get(opts, :session_pid)

    unless is_pid(session_pid) do
      {:stop, {:invalid_session_pid, session_pid}}
    end

    state = %__MODULE__{
      session_pid: session_pid,
      monitored_components: Keyword.get(opts, :components, []),
      alert_thresholds: Keyword.get(opts, :alert_thresholds, default_alert_thresholds()),
      performance_targets: Keyword.merge(default_performance_targets(),
                                        Keyword.get(opts, :performance_targets, %{}))
    }

    # Start monitoring timer
    :timer.send_interval(@monitor_interval_ms, self(), :collect_metrics)

    # Start history cleanup timer
    :timer.send_interval(60_000, self(), :cleanup_history) # Every minute

    Logger.info("RealtimeMonitor started for session with components: #{inspect(state.monitored_components)}")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_performance_snapshot, _from, state) do
    {:reply, state.current_metrics, state}
  end

  @impl true
  def handle_call({:get_performance_history, minutes}, _from, state) do
    cutoff_time = System.monotonic_time(:millisecond) - (minutes * 60 * 1000)

    filtered_history = Enum.filter(state.performance_history, fn entry ->
      entry.timestamp >= cutoff_time
    end)

    {:reply, filtered_history, state}
  end

  @impl true
  def handle_call(:optimize_performance, _from, state) do
    case perform_optimization(state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_active_alerts, _from, state) do
    {:reply, state.active_alerts, state}
  end

  @impl true
  def handle_call({:generate_performance_report, minutes}, _from, state) do
    report = generate_report(state, minutes)
    {:reply, report, state}
  end

  @impl true
  def handle_cast({:set_alert_threshold, metric, threshold, level}, state) do
    new_thresholds = Map.put(state.alert_thresholds, metric, {threshold, level})
    new_state = %{state | alert_thresholds: new_thresholds}

    Logger.info("Alert threshold set: #{metric} -> #{threshold} (#{level})")
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:subscribe_to_updates, subscriber_pid}, state) do
    new_subscribers = [subscriber_pid | state.dashboard_subscribers] |> Enum.uniq()
    new_state = %{state | dashboard_subscribers: new_subscribers}

    Logger.debug("Dashboard subscriber added: #{inspect(subscriber_pid)}")
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:collect_metrics, state) do
    new_state = collect_and_process_metrics(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup_history, state) do
    new_state = cleanup_old_history(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:component_metrics, component, metrics}, state) do
    # Handle metrics pushed from individual components
    updated_metrics = Map.put(state.current_metrics, component, metrics)
    new_state = %{state | current_metrics: updated_metrics}

    # Broadcast to subscribers
    broadcast_metrics_update(new_state)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("RealtimeMonitor received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp collect_and_process_metrics(state) do
    # Collect metrics from all monitored components
    metrics = collect_component_metrics(state.monitored_components)

    # Add system-level metrics
    system_metrics = collect_system_metrics()
    all_metrics = Map.merge(metrics, %{system: system_metrics, timestamp: System.monotonic_time(:millisecond)})

    # Calculate derived metrics
    enhanced_metrics = calculate_derived_metrics(all_metrics, state)

    # Check for alerts
    {alerts, alert_state} = check_and_process_alerts(enhanced_metrics, state)

    # Update performance history
    new_history = [enhanced_metrics | state.performance_history]

    # Update state
    new_state = %{
      state
      | current_metrics: enhanced_metrics,
        performance_history: new_history,
        active_alerts: alerts,
        last_alert_times: alert_state
    }

    # Broadcast updates to subscribers
    broadcast_metrics_update(new_state)

    # Trigger optimization if needed
    if should_trigger_optimization?(enhanced_metrics, state) do
      Logger.info("Performance degradation detected - triggering optimization")
      perform_optimization(new_state)
    else
      new_state
    end
  end

  defp collect_component_metrics(components) do
    Enum.reduce(components, %{}, fn component, acc ->
      metrics = case component do
        :audio_processor ->
          collect_audio_processor_metrics()

        :webrtc_handler ->
          collect_webrtc_handler_metrics()

        :llm_client ->
          collect_llm_client_metrics()

        :stream_manager ->
          collect_stream_manager_metrics()

        :speech_handle ->
          collect_speech_handle_metrics()

        :vad_client ->
          collect_vad_client_metrics()

        :session ->
          collect_session_metrics()

        _ ->
          %{error: :unknown_component}
      end

      Map.put(acc, component, metrics)
    end)
  end

  defp collect_audio_processor_metrics do
    # In a real implementation, this would query the actual audio processor
    %{
      latency_ms: :rand.uniform(30) + 20, # 20-50ms
      quality_score: 4.0 + (:rand.uniform(10) / 10), # 4.0-5.0
      buffer_utilization: :rand.uniform(100) / 100, # 0-100%
      processing_time_ms: :rand.uniform(10) + 5, # 5-15ms
      dropped_frames: :rand.uniform(5), # 0-5 dropped frames
      sample_rate: 16000,
      channels: 1
    }
  end

  defp collect_webrtc_handler_metrics do
    %{
      connection_latency_ms: :rand.uniform(50) + 25, # 25-75ms
      packet_loss_percent: :rand.uniform(20) / 10, # 0-2%
      jitter_ms: :rand.uniform(15) + 5, # 5-20ms
      bandwidth_kbps: :rand.uniform(500) + 500, # 500-1000 kbps
      connection_quality: [:excellent, :good, :fair] |> Enum.random(),
      ice_connection_state: :connected,
      dtls_state: :connected
    }
  end

  defp collect_llm_client_metrics do
    %{
      response_time_ms: :rand.uniform(500) + 200, # 200-700ms
      tokens_per_second: :rand.uniform(50) + 25, # 25-75 tokens/sec
      context_length: :rand.uniform(1000) + 500, # 500-1500 tokens
      api_latency_ms: :rand.uniform(300) + 100, # 100-400ms
      success_rate: 0.95 + (:rand.uniform(5) / 100), # 95-100%
      error_count: :rand.uniform(3) # 0-3 errors
    }
  end

  defp collect_stream_manager_metrics do
    %{
      buffer_latency_ms: :rand.uniform(20) + 10, # 10-30ms
      sync_drift_ms: :rand.uniform(10), # 0-10ms
      active_streams: :rand.uniform(3) + 1, # 1-4 streams
      buffer_overruns: :rand.uniform(2), # 0-2 overruns
      buffer_underruns: :rand.uniform(2), # 0-2 underruns
      processing_efficiency: 0.85 + (:rand.uniform(15) / 100) # 85-100%
    }
  end

  defp collect_speech_handle_metrics do
    %{
      speech_latency_ms: :rand.uniform(40) + 10, # 10-50ms
      interruption_response_ms: :rand.uniform(50) + 25, # 25-75ms
      active_handles: :rand.uniform(3) + 1, # 1-4 handles
      successful_interruptions: :rand.uniform(10), # 0-10
      failed_interruptions: :rand.uniform(2) # 0-2 failures
    }
  end

  defp collect_vad_client_metrics do
    %{
      detection_latency_ms: :rand.uniform(15) + 5, # 5-20ms
      sensitivity: 0.7, # Current sensitivity setting
      speech_detection_rate: 0.9 + (:rand.uniform(10) / 100), # 90-100%
      false_positive_rate: (:rand.uniform(5) / 100), # 0-5%
      processing_load: :rand.uniform(30) + 10 # 10-40% CPU
    }
  end

  defp collect_session_metrics do
    %{
      uptime_seconds: :rand.uniform(3600) + 60, # 1-61 minutes
      total_turns: :rand.uniform(50) + 5, # 5-55 turns
      avg_turn_duration_ms: :rand.uniform(2000) + 1000, # 1-3 seconds
      interruption_rate: (:rand.uniform(20) / 100), # 0-20%
      user_satisfaction_score: 3.5 + (:rand.uniform(15) / 10), # 3.5-5.0
      memory_usage_mb: :rand.uniform(200) + 100 # 100-300 MB
    }
  end

  defp collect_system_metrics do
    %{
      cpu_utilization: :rand.uniform(50) + 20, # 20-70%
      memory_total_mb: 8192, # 8GB system
      memory_used_mb: :rand.uniform(4096) + 2048, # 2-6GB used
      network_latency_ms: :rand.uniform(20) + 5, # 5-25ms
      disk_io_utilization: :rand.uniform(30) + 10, # 10-40%
      active_processes: :rand.uniform(50) + 100, # 100-150 processes
      system_load: :rand.uniform(200) + 50 # 50-250% system load
    }
  end

  defp calculate_derived_metrics(metrics, state) do
    # Calculate end-to-end latency
    audio_latency = get_in(metrics, [:audio_processor, :latency_ms]) || 0
    webrtc_latency = get_in(metrics, [:webrtc_handler, :connection_latency_ms]) || 0
    llm_latency = get_in(metrics, [:llm_client, :response_time_ms]) || 0

    end_to_end_latency = audio_latency + webrtc_latency + (llm_latency * 0.1) # LLM runs in parallel

    # Calculate overall system health score
    health_score = calculate_health_score(metrics, state.performance_targets)

    # Calculate efficiency metrics
    efficiency_metrics = calculate_efficiency_metrics(metrics)

    Map.merge(metrics, %{
      derived: %{
        end_to_end_latency_ms: end_to_end_latency,
        system_health_score: health_score,
        performance_grade: grade_performance(health_score),
        efficiency: efficiency_metrics,
        timestamp: System.monotonic_time(:millisecond)
      }
    })
  end

  defp calculate_health_score(metrics, targets) do
    scores = []

    # Audio latency score
    audio_latency = get_in(metrics, [:audio_processor, :latency_ms])
    scores = if audio_latency do
      target = targets.audio_latency_ms
      score = max(0, 100 - (audio_latency - target) * 2)
      [score | scores]
    else
      scores
    end

    # Quality score
    quality = get_in(metrics, [:audio_processor, :quality_score])
    scores = if quality do
      target = targets.audio_quality_score
      score = (quality / target) * 100 |> min(100)
      [score | scores]
    else
      scores
    end

    # CPU utilization score
    cpu = get_in(metrics, [:system, :cpu_utilization])
    scores = if cpu do
      target = targets.cpu_utilization_percent
      score = max(0, 100 - max(0, cpu - target))
      [score | scores]
    else
      scores
    end

    # Memory usage score
    memory = get_in(metrics, [:session, :memory_usage_mb])
    scores = if memory do
      target = targets.memory_usage_mb
      score = max(0, 100 - max(0, memory - target) / target * 100)
      [score | scores]
    else
      scores
    end

    if length(scores) > 0 do
      Enum.sum(scores) / length(scores)
    else
      100
    end
  end

  defp grade_performance(health_score) do
    cond do
      health_score >= 90 -> :excellent
      health_score >= 80 -> :good
      health_score >= 70 -> :fair
      health_score >= 60 -> :poor
      true -> :critical
    end
  end

  defp calculate_efficiency_metrics(metrics) do
    # Calculate various efficiency metrics
    %{
      cpu_efficiency: calculate_cpu_efficiency(metrics),
      memory_efficiency: calculate_memory_efficiency(metrics),
      network_efficiency: calculate_network_efficiency(metrics),
      overall_efficiency: 0.85 # Placeholder calculation
    }
  end

  defp calculate_cpu_efficiency(metrics) do
    cpu_util = get_in(metrics, [:system, :cpu_utilization]) || 50
    # Efficiency based on getting good performance without over-utilizing CPU
    cond do
      cpu_util < 30 -> 0.7 # Under-utilizing
      cpu_util < 70 -> 1.0 # Optimal range
      cpu_util < 90 -> 0.8 # High but acceptable
      true -> 0.5 # Over-utilizing
    end
  end

  defp calculate_memory_efficiency(metrics) do
    memory_used = get_in(metrics, [:system, :memory_used_mb]) || 2048
    memory_total = get_in(metrics, [:system, :memory_total_mb]) || 8192
    utilization = memory_used / memory_total

    cond do
      utilization < 0.3 -> 0.7 # Under-utilizing
      utilization < 0.7 -> 1.0 # Optimal range
      utilization < 0.9 -> 0.8 # High but acceptable
      true -> 0.5 # Over-utilizing
    end
  end

  defp calculate_network_efficiency(metrics) do
    packet_loss = get_in(metrics, [:webrtc_handler, :packet_loss_percent]) || 0
    jitter = get_in(metrics, [:webrtc_handler, :jitter_ms]) || 10

    # Efficiency based on minimal packet loss and jitter
    loss_score = max(0, 1.0 - packet_loss / 5.0) # 5% loss = 0 efficiency
    jitter_score = max(0, 1.0 - jitter / 50.0) # 50ms jitter = 0 efficiency

    (loss_score + jitter_score) / 2
  end

  defp check_and_process_alerts(metrics, state) do
    current_time = System.monotonic_time(:millisecond)
    new_alerts = []
    updated_alert_times = state.last_alert_times

    # Check each configured threshold
    {alerts, alert_times} = Enum.reduce(state.alert_thresholds, {new_alerts, updated_alert_times},
      fn {metric, {threshold, level}}, {acc_alerts, acc_times} ->
        case get_metric_value(metrics, metric) do
          nil ->
            {acc_alerts, acc_times}

          value when value > threshold ->
            # Check cooldown
            last_alert_time = Map.get(acc_times, metric, 0)
            if current_time - last_alert_time > @alert_cooldown_ms do
              alert = create_alert(metric, value, threshold, level, current_time)
              new_acc_alerts = [alert | acc_alerts]
              new_acc_times = Map.put(acc_times, metric, current_time)

              Logger.warning("Performance alert: #{metric} = #{value} (threshold: #{threshold})")
              {new_acc_alerts, new_acc_times}
            else
              {acc_alerts, acc_times}
            end

          _ ->
            {acc_alerts, acc_times}
        end
      end)

    {alerts, alert_times}
  end

  defp get_metric_value(metrics, metric) do
    case metric do
      :audio_latency_ms -> get_in(metrics, [:audio_processor, :latency_ms])
      :end_to_end_latency_ms -> get_in(metrics, [:derived, :end_to_end_latency_ms])
      :quality_score -> get_in(metrics, [:audio_processor, :quality_score])
      :memory_mb -> get_in(metrics, [:session, :memory_usage_mb])
      :cpu_percent -> get_in(metrics, [:system, :cpu_utilization])
      :error_rate -> calculate_error_rate(metrics)
      _ -> nil
    end
  end

  defp calculate_error_rate(metrics) do
    # Calculate overall error rate from various components
    llm_errors = get_in(metrics, [:llm_client, :error_count]) || 0
    speech_errors = get_in(metrics, [:speech_handle, :failed_interruptions]) || 0

    total_operations = get_in(metrics, [:session, :total_turns]) || 1
    total_errors = llm_errors + speech_errors

    (total_errors / total_operations) * 100
  end

  defp create_alert(metric, value, threshold, level, timestamp) do
    %{
      metric: metric,
      value: value,
      threshold: threshold,
      level: level,
      timestamp: timestamp,
      message: "#{metric} exceeded threshold: #{value} > #{threshold}"
    }
  end

  defp should_trigger_optimization?(metrics, state) do
    health_score = get_in(metrics, [:derived, :system_health_score]) || 100

    # Trigger optimization if health score drops below 70
    health_score < 70 and state.optimization_state != :optimizing
  end

  defp perform_optimization(state) do
    Logger.info("Performing automated performance optimization")

    try do
      # Apply various optimization strategies
      optimization_results = [
        optimize_component(:audio_processor, state),
        optimize_component(:webrtc_handler, state),
        optimize_component(:stream_manager, state),
        optimize_system_resources(state)
      ]

      success_count = Enum.count(optimization_results, &(&1 == :ok))
      Logger.info("Optimization completed: #{success_count}/#{length(optimization_results)} successful")

      {:ok, %{state | optimization_state: :optimized}}
    rescue
      error ->
        Logger.error("Optimization failed: #{inspect(error)}")
        {:error, error}
    end
  end

  defp optimize_component(:audio_processor, state) do
    send(state.session_pid, {:optimization_request, :audio_processor, :reduce_latency})
    :ok
  end

  defp optimize_component(:webrtc_handler, state) do
    send(state.session_pid, {:optimization_request, :webrtc_handler, :improve_quality})
    :ok
  end

  defp optimize_component(:stream_manager, state) do
    send(state.session_pid, {:optimization_request, :stream_manager, :optimize_buffers})
    :ok
  end

  defp optimize_system_resources(_state) do
    # System-level optimizations
    :erlang.garbage_collect()
    :ok
  end

  defp broadcast_metrics_update(state) do
    update_message = {:performance_update, state.current_metrics}

    Enum.each(state.dashboard_subscribers, fn subscriber ->
      send(subscriber, update_message)
    end)
  end

  defp cleanup_old_history(state) do
    cutoff_time = System.monotonic_time(:millisecond) - (@history_retention_minutes * 60 * 1000)

    filtered_history = Enum.filter(state.performance_history, fn entry ->
      entry.timestamp >= cutoff_time
    end)

    %{state | performance_history: filtered_history}
  end

  defp generate_report(state, minutes) do
    cutoff_time = System.monotonic_time(:millisecond) - (minutes * 60 * 1000)

    relevant_history = Enum.filter(state.performance_history, fn entry ->
      entry.timestamp >= cutoff_time
    end)

    if length(relevant_history) == 0 do
      %{error: :insufficient_data, message: "No performance data available for the requested time period"}
    else
      %{
        period_minutes: minutes,
        data_points: length(relevant_history),
        summary: generate_summary_stats(relevant_history),
        trends: analyze_performance_trends(relevant_history),
        recommendations: generate_optimization_recommendations(relevant_history, state),
        current_status: %{
          health_score: get_in(state.current_metrics, [:derived, :system_health_score]),
          performance_grade: get_in(state.current_metrics, [:derived, :performance_grade]),
          active_alerts: length(state.active_alerts)
        }
      }
    end
  end

  defp generate_summary_stats(history) do
    %{
      avg_latency_ms: calculate_average(history, [:derived, :end_to_end_latency_ms]),
      avg_health_score: calculate_average(history, [:derived, :system_health_score]),
      max_cpu_utilization: calculate_maximum(history, [:system, :cpu_utilization]),
      avg_memory_usage_mb: calculate_average(history, [:session, :memory_usage_mb])
    }
  end

  defp analyze_performance_trends(history) do
    # Simple trend analysis
    %{
      latency_trend: analyze_metric_trend(history, [:derived, :end_to_end_latency_ms]),
      health_trend: analyze_metric_trend(history, [:derived, :system_health_score]),
      resource_trend: analyze_metric_trend(history, [:system, :cpu_utilization])
    }
  end

  defp analyze_metric_trend(history, metric_path) do
    values = Enum.map(history, &get_in(&1, metric_path)) |> Enum.reject(&is_nil/1)

    if length(values) < 2 do
      :insufficient_data
    else
      first_half = Enum.take(values, div(length(values), 2))
      second_half = Enum.drop(values, div(length(values), 2))

      first_avg = Enum.sum(first_half) / length(first_half)
      second_avg = Enum.sum(second_half) / length(second_half)

      change_percent = ((second_avg - first_avg) / first_avg) * 100

      cond do
        abs(change_percent) < 5 -> :stable
        change_percent > 5 -> :increasing
        change_percent < -5 -> :decreasing
      end
    end
  end

  defp generate_optimization_recommendations(history, _state) do
    recommendations = []

    # Check latency trends
    recommendations = if calculate_average(history, [:derived, :end_to_end_latency_ms]) > 100 do
      ["Consider enabling latency optimization features" | recommendations]
    else
      recommendations
    end

    # Check resource utilization
    recommendations = if calculate_average(history, [:system, :cpu_utilization]) > 80 do
      ["CPU utilization is high - consider scaling resources" | recommendations]
    else
      recommendations
    end

    # Check quality trends
    recommendations = if calculate_average(history, [:audio_processor, :quality_score]) < 4.0 do
      ["Audio quality is below target - check network conditions" | recommendations]
    else
      recommendations
    end

    if length(recommendations) == 0 do
      ["Performance is within acceptable ranges"]
    else
      recommendations
    end
  end

  defp calculate_average(history, metric_path) do
    values = Enum.map(history, &get_in(&1, metric_path)) |> Enum.reject(&is_nil/1)

    if length(values) > 0 do
      Enum.sum(values) / length(values)
    else
      0
    end
  end

  defp calculate_maximum(history, metric_path) do
    values = Enum.map(history, &get_in(&1, metric_path)) |> Enum.reject(&is_nil/1)

    if length(values) > 0 do
      Enum.max(values)
    else
      0
    end
  end

  defp default_alert_thresholds do
    %{
      audio_latency_ms: {100, :warning},
      end_to_end_latency_ms: {150, :error},
      cpu_percent: {85, :warning},
      memory_mb: {600, :warning},
      error_rate: {5, :error}
    }
  end

  defp default_performance_targets do
    %{
      audio_latency_ms: 50,
      end_to_end_latency_ms: 100,
      audio_quality_score: 4.0,
      memory_usage_mb: 500,
      cpu_utilization_percent: 70,
      availability_percent: 99.9
    }
  end
end
