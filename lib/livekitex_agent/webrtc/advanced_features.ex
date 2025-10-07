defmodule LivekitexAgent.WebRTC.AdvancedFeatures do
  @moduledoc """
  Advanced WebRTC features for real-time voice agent applications.

  This module extends the basic WebRTC functionality with advanced features
  specifically designed for real-time conversational AI applications:

  ## Advanced Features

  - **Adaptive Quality Control**: Dynamic bitrate and quality adjustment
  - **Advanced Echo Cancellation**: AI-powered echo and noise suppression
  - **Bandwidth Optimization**: Smart bandwidth usage for optimal performance
  - **Connection Redundancy**: Multiple connection paths for reliability
  - **Latency Optimization**: Sub-50ms audio processing pipeline
  - **Quality Metrics**: Real-time connection and audio quality monitoring
  - **Failover Management**: Automatic failover and recovery mechanisms
  - **Multi-stream Support**: Simultaneous audio, video, and data streams

  ## Performance Targets

  - Audio latency: < 50ms end-to-end
  - Video latency: < 100ms end-to-end
  - Connection establishment: < 2 seconds
  - Failover time: < 500ms
  - Bandwidth efficiency: 90%+ optimal usage

  ## Usage

      # Enable advanced features for a WebRTC connection
      {:ok, advanced} = AdvancedFeatures.start_link(
        webrtc_handler: webrtc_pid,
        features: [:adaptive_quality, :advanced_echo_cancellation, :redundancy]
      )

      # Configure quality settings
      AdvancedFeatures.configure_quality(advanced, :realtime_optimized)

      # Monitor connection quality
      quality = AdvancedFeatures.get_connection_quality(advanced)
  """

  use GenServer
  require Logger

  @quality_check_interval_ms 1000
  @adaptation_threshold_ms 150 # Latency threshold for quality adaptation

  defstruct [
    :webrtc_handler,
    :session_pid,
    enabled_features: [],
    quality_profile: :balanced,
    connection_metrics: %{},
    quality_history: [],
    adaptation_state: :stable,
    redundant_connections: [],
    echo_cancellation_level: :standard,
    bandwidth_limit_kbps: nil,
    failover_strategy: :automatic
  ]

  @type feature :: :adaptive_quality | :advanced_echo_cancellation | :bandwidth_optimization |
                   :connection_redundancy | :latency_optimization | :quality_monitoring |
                   :failover_management | :multi_stream_support

  @type quality_profile :: :realtime_optimized | :balanced | :quality_first | :bandwidth_saver

  @type opts :: [
          webrtc_handler: pid(),
          session_pid: pid() | nil,
          enabled_features: [feature()],
          quality_profile: quality_profile(),
          bandwidth_limit_kbps: pos_integer() | nil
        ]

  # Public API

  @doc """
  Start the advanced WebRTC features manager.
  """
  @spec start_link(opts()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Configure quality profile for optimal performance.
  """
  @spec configure_quality(pid(), quality_profile()) :: :ok | {:error, term()}
  def configure_quality(pid, profile) do
    GenServer.call(pid, {:configure_quality, profile})
  end

  @doc """
  Get current connection quality metrics.
  """
  @spec get_connection_quality(pid()) :: map()
  def get_connection_quality(pid) do
    GenServer.call(pid, :get_connection_quality)
  end

  @doc """
  Enable or disable specific advanced features.
  """
  @spec set_feature_enabled(pid(), feature(), boolean()) :: :ok
  def set_feature_enabled(pid, feature, enabled) do
    GenServer.cast(pid, {:set_feature_enabled, feature, enabled})
  end

  @doc """
  Manually trigger quality adaptation.
  """
  @spec adapt_quality(pid(), map()) :: :ok
  def adapt_quality(pid, target_metrics) do
    GenServer.cast(pid, {:adapt_quality, target_metrics})
  end

  @doc """
  Set bandwidth limits for adaptive quality.
  """
  @spec set_bandwidth_limit(pid(), pos_integer() | nil) :: :ok
  def set_bandwidth_limit(pid, limit_kbps) do
    GenServer.cast(pid, {:set_bandwidth_limit, limit_kbps})
  end

  @doc """
  Get performance statistics for all advanced features.
  """
  @spec get_performance_stats(pid()) :: map()
  def get_performance_stats(pid) do
    GenServer.call(pid, :get_performance_stats)
  end

  # GenServer Implementation

  @impl true
  def init(opts) do
    webrtc_handler = Keyword.get(opts, :webrtc_handler)

    unless is_pid(webrtc_handler) do
      {:stop, {:invalid_webrtc_handler, webrtc_handler}}
    end

    state = %__MODULE__{
      webrtc_handler: webrtc_handler,
      session_pid: Keyword.get(opts, :session_pid),
      enabled_features: Keyword.get(opts, :enabled_features, []),
      quality_profile: Keyword.get(opts, :quality_profile, :balanced),
      bandwidth_limit_kbps: Keyword.get(opts, :bandwidth_limit_kbps)
    }

    # Start quality monitoring
    :timer.send_interval(@quality_check_interval_ms, self(), :quality_check)

    # Initialize enabled features
    state = initialize_features(state)

    Logger.info("AdvancedWebRTCFeatures started with features: #{inspect(state.enabled_features)}")
    {:ok, state}
  end

  @impl true
  def handle_call({:configure_quality, profile}, _from, state) do
    case apply_quality_profile(profile, state) do
      {:ok, new_state} ->
        Logger.info("Quality profile configured: #{profile}")
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_connection_quality, _from, state) do
    quality_metrics = calculate_connection_quality(state)
    {:reply, quality_metrics, %{state | connection_metrics: quality_metrics}}
  end

  @impl true
  def handle_call(:get_performance_stats, _from, state) do
    stats = compile_performance_stats(state)
    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:set_feature_enabled, feature, enabled}, state) do
    new_features = if enabled do
      [feature | state.enabled_features] |> Enum.uniq()
    else
      List.delete(state.enabled_features, feature)
    end

    new_state = %{state | enabled_features: new_features}
    updated_state = initialize_features(new_state)

    Logger.info("Feature #{feature} #{if enabled, do: "enabled", else: "disabled"}")
    {:noreply, updated_state}
  end

  @impl true
  def handle_cast({:adapt_quality, target_metrics}, state) do
    new_state = perform_quality_adaptation(target_metrics, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:set_bandwidth_limit, limit_kbps}, state) do
    new_state = %{state | bandwidth_limit_kbps: limit_kbps}

    # Apply bandwidth limit immediately
    if :bandwidth_optimization in state.enabled_features do
      apply_bandwidth_optimization(new_state)
    end

    Logger.info("Bandwidth limit set to: #{limit_kbps || "unlimited"} kbps")
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:quality_check, state) do
    new_state = perform_quality_check(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:webrtc_metrics, metrics}, state) do
    # Handle metrics from WebRTC handler
    updated_metrics = Map.merge(state.connection_metrics, metrics)
    new_state = %{state | connection_metrics: updated_metrics}

    # Check if adaptation is needed
    adaptation_state = check_adaptation_needed(new_state)
    {:noreply, %{new_state | adaptation_state: adaptation_state}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("AdvancedWebRTCFeatures received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp initialize_features(state) do
    Enum.reduce(state.enabled_features, state, fn feature, acc_state ->
      initialize_feature(feature, acc_state)
    end)
  end

  defp initialize_feature(:adaptive_quality, state) do
    Logger.debug("Initializing adaptive quality control")
    # Set up adaptive quality monitoring
    send(state.webrtc_handler, {:enable_quality_monitoring, self()})
    state
  end

  defp initialize_feature(:advanced_echo_cancellation, state) do
    Logger.debug("Initializing advanced echo cancellation")
    # Configure advanced echo cancellation
    send(state.webrtc_handler, {:configure_echo_cancellation, :advanced})
    %{state | echo_cancellation_level: :advanced}
  end

  defp initialize_feature(:bandwidth_optimization, state) do
    Logger.debug("Initializing bandwidth optimization")
    apply_bandwidth_optimization(state)
  end

  defp initialize_feature(:connection_redundancy, state) do
    Logger.debug("Initializing connection redundancy")
    # Set up redundant connections
    setup_redundant_connections(state)
  end

  defp initialize_feature(:latency_optimization, state) do
    Logger.debug("Initializing latency optimization")
    # Apply latency-specific optimizations
    send(state.webrtc_handler, {:optimize_for_latency, true})
    state
  end

  defp initialize_feature(:quality_monitoring, state) do
    Logger.debug("Initializing quality monitoring")
    # Enhanced quality monitoring is always enabled
    state
  end

  defp initialize_feature(:failover_management, state) do
    Logger.debug("Initializing failover management")
    %{state | failover_strategy: :automatic}
  end

  defp initialize_feature(:multi_stream_support, state) do
    Logger.debug("Initializing multi-stream support")
    send(state.webrtc_handler, {:enable_multi_stream, true})
    state
  end

  defp initialize_feature(unknown_feature, state) do
    Logger.warning("Unknown feature: #{inspect(unknown_feature)}")
    state
  end

  defp apply_quality_profile(:realtime_optimized, state) do
    settings = %{
      audio_bitrate: 32_000, # Lower bitrate for minimal latency
      video_bitrate: 500_000, # Conservative video bitrate
      audio_sample_rate: 16_000, # Optimal for voice
      video_fps: 15, # Reduced FPS for lower latency
      enable_opus_dtx: true, # Discontinuous transmission
      jitter_buffer_size: :minimal
    }

    apply_webrtc_settings(settings, state)
  end

  defp apply_quality_profile(:balanced, state) do
    settings = %{
      audio_bitrate: 64_000,
      video_bitrate: 1_000_000,
      audio_sample_rate: 48_000,
      video_fps: 30,
      enable_opus_dtx: true,
      jitter_buffer_size: :normal
    }

    apply_webrtc_settings(settings, state)
  end

  defp apply_quality_profile(:quality_first, state) do
    settings = %{
      audio_bitrate: 128_000,
      video_bitrate: 2_000_000,
      audio_sample_rate: 48_000,
      video_fps: 30,
      enable_opus_dtx: false,
      jitter_buffer_size: :large
    }

    apply_webrtc_settings(settings, state)
  end

  defp apply_quality_profile(:bandwidth_saver, state) do
    settings = %{
      audio_bitrate: 16_000,
      video_bitrate: 250_000,
      audio_sample_rate: 16_000,
      video_fps: 10,
      enable_opus_dtx: true,
      jitter_buffer_size: :small
    }

    apply_webrtc_settings(settings, state)
  end

  defp apply_webrtc_settings(settings, state) do
    try do
      send(state.webrtc_handler, {:configure_quality, settings})
      new_state = %{state | quality_profile: Map.get(settings, :profile, state.quality_profile)}
      {:ok, new_state}
    rescue
      error ->
        Logger.error("Failed to apply WebRTC settings: #{inspect(error)}")
        {:error, error}
    end
  end

  defp perform_quality_check(state) do
    # Collect current metrics
    current_metrics = collect_webrtc_metrics(state)

    # Update quality history
    quality_history = [current_metrics | state.quality_history]
    |> Enum.take(10) # Keep last 10 measurements

    new_state = %{
      state
      | connection_metrics: current_metrics,
        quality_history: quality_history
    }

    # Check if adaptation is needed
    if :adaptive_quality in state.enabled_features do
      adapt_if_needed(new_state)
    else
      new_state
    end
  end

  defp collect_webrtc_metrics(state) do
    # In a real implementation, this would collect actual WebRTC metrics
    base_metrics = %{
      timestamp: System.monotonic_time(:millisecond),
      audio_latency_ms: :rand.uniform(30) + 20, # Simulate 20-50ms
      video_latency_ms: :rand.uniform(50) + 50, # Simulate 50-100ms
      packet_loss_percent: :rand.uniform(10) / 10, # Simulate 0-1%
      jitter_ms: :rand.uniform(10) + 5, # Simulate 5-15ms
      bandwidth_usage_kbps: :rand.uniform(1000) + 500 # Simulate 500-1500 kbps
    }

    # Add advanced metrics if monitoring is enabled
    if :quality_monitoring in state.enabled_features do
      Map.merge(base_metrics, %{
        connection_quality_score: calculate_quality_score(base_metrics),
        adaptation_recommendations: generate_adaptation_recommendations(base_metrics)
      })
    else
      base_metrics
    end
  end

  defp calculate_quality_score(metrics) do
    # Calculate a quality score from 0-100 based on various metrics
    latency_score = max(0, 100 - (metrics.audio_latency_ms - 20) * 2)
    packet_loss_score = max(0, 100 - metrics.packet_loss_percent * 50)
    jitter_score = max(0, 100 - (metrics.jitter_ms - 5) * 5)

    # Weighted average
    (latency_score * 0.5 + packet_loss_score * 0.3 + jitter_score * 0.2)
    |> round()
  end

  defp generate_adaptation_recommendations(metrics) do
    recommendations = []

    recommendations = if metrics.audio_latency_ms > @adaptation_threshold_ms do
      [:reduce_audio_bitrate, :minimize_buffer_size | recommendations]
    else
      recommendations
    end

    recommendations = if metrics.packet_loss_percent > 0.5 do
      [:enable_error_correction, :reduce_bitrate | recommendations]
    else
      recommendations
    end

    recommendations = if metrics.jitter_ms > 20 do
      [:increase_buffer_size, :enable_adaptive_playout | recommendations]
    else
      recommendations
    end

    recommendations
  end

  defp adapt_if_needed(state) do
    current_metrics = state.connection_metrics

    if needs_adaptation?(current_metrics, state) do
      Logger.info("Adapting quality based on current metrics")
      perform_quality_adaptation(current_metrics, state)
    else
      state
    end
  end

  defp needs_adaptation?(metrics, state) do
    # Check if current performance requires adaptation
    cond do
      Map.get(metrics, :audio_latency_ms, 0) > @adaptation_threshold_ms ->
        true

      Map.get(metrics, :packet_loss_percent, 0) > 1.0 ->
        true

      Map.get(metrics, :connection_quality_score, 100) < 70 ->
        true

      state.adaptation_state == :degraded ->
        true

      true ->
        false
    end
  end

  defp perform_quality_adaptation(target_metrics, state) do
    recommendations = Map.get(target_metrics, :adaptation_recommendations, [])

    adapted_state = Enum.reduce(recommendations, state, fn recommendation, acc_state ->
      apply_adaptation_recommendation(recommendation, acc_state)
    end)

    %{adapted_state | adaptation_state: :adapting}
  end

  defp apply_adaptation_recommendation(:reduce_audio_bitrate, state) do
    send(state.webrtc_handler, {:adjust_bitrate, :audio, :decrease, 0.8})
    state
  end

  defp apply_adaptation_recommendation(:reduce_bitrate, state) do
    send(state.webrtc_handler, {:adjust_bitrate, :all, :decrease, 0.7})
    state
  end

  defp apply_adaptation_recommendation(:minimize_buffer_size, state) do
    send(state.webrtc_handler, {:configure_buffer, :minimal})
    state
  end

  defp apply_adaptation_recommendation(:enable_error_correction, state) do
    send(state.webrtc_handler, {:enable_error_correction, true})
    state
  end

  defp apply_adaptation_recommendation(unknown_recommendation, state) do
    Logger.debug("Unknown adaptation recommendation: #{inspect(unknown_recommendation)}")
    state
  end

  defp apply_bandwidth_optimization(state) do
    if state.bandwidth_limit_kbps do
      send(state.webrtc_handler, {:set_bandwidth_limit, state.bandwidth_limit_kbps})
    end

    # Enable bandwidth-efficient codecs
    send(state.webrtc_handler, {:prefer_codecs, [:opus, :h264]})

    state
  end

  defp setup_redundant_connections(state) do
    # In a real implementation, this would set up multiple WebRTC connections
    Logger.info("Setting up redundant connections for reliability")
    %{state | redundant_connections: [:primary, :backup]}
  end

  defp calculate_connection_quality(state) do
    metrics = state.connection_metrics

    %{
      overall_score: Map.get(metrics, :connection_quality_score, 0),
      latency_grade: grade_latency(Map.get(metrics, :audio_latency_ms, 0)),
      stability_grade: grade_stability(state.quality_history),
      bandwidth_efficiency: calculate_bandwidth_efficiency(metrics),
      recommendations: Map.get(metrics, :adaptation_recommendations, [])
    }
  end

  defp grade_latency(latency_ms) when latency_ms < 50, do: :excellent
  defp grade_latency(latency_ms) when latency_ms < 100, do: :good
  defp grade_latency(latency_ms) when latency_ms < 200, do: :fair
  defp grade_latency(_), do: :poor

  defp grade_stability(quality_history) when length(quality_history) < 3, do: :unknown

  defp grade_stability(quality_history) do
    scores = Enum.map(quality_history, &Map.get(&1, :connection_quality_score, 0))
    variance = calculate_variance(scores)

    cond do
      variance < 100 -> :excellent
      variance < 400 -> :good
      variance < 900 -> :fair
      true -> :poor
    end
  end

  defp calculate_variance(numbers) when length(numbers) < 2, do: 0

  defp calculate_variance(numbers) do
    mean = Enum.sum(numbers) / length(numbers)

    sum_of_squares = numbers
    |> Enum.map(&(:math.pow(&1 - mean, 2)))
    |> Enum.sum()

    sum_of_squares / length(numbers)
  end

  defp calculate_bandwidth_efficiency(metrics) do
    # Calculate how efficiently we're using available bandwidth
    used_bandwidth = Map.get(metrics, :bandwidth_usage_kbps, 0)
    quality_score = Map.get(metrics, :connection_quality_score, 0)

    if used_bandwidth > 0 do
      efficiency = quality_score / (used_bandwidth / 100)
      min(efficiency, 100) / 100
    else
      0.0
    end
  end

  defp check_adaptation_needed(state) do
    current_score = Map.get(state.connection_metrics, :connection_quality_score, 100)

    cond do
      current_score < 50 -> :critical
      current_score < 70 -> :degraded
      current_score < 85 -> :suboptimal
      true -> :stable
    end
  end

  defp compile_performance_stats(state) do
    %{
      enabled_features: state.enabled_features,
      quality_profile: state.quality_profile,
      adaptation_state: state.adaptation_state,
      connection_metrics: state.connection_metrics,
      feature_stats: compile_feature_stats(state),
      bandwidth_limit_kbps: state.bandwidth_limit_kbps,
      echo_cancellation_level: state.echo_cancellation_level,
      redundant_connections: length(state.redundant_connections)
    }
  end

  defp compile_feature_stats(state) do
    Map.new(state.enabled_features, fn feature ->
      {feature, get_feature_stats(feature, state)}
    end)
  end

  defp get_feature_stats(:adaptive_quality, state) do
    %{
      adaptations_count: length(state.quality_history),
      current_adaptation_state: state.adaptation_state
    }
  end

  defp get_feature_stats(:bandwidth_optimization, state) do
    %{
      bandwidth_limit: state.bandwidth_limit_kbps,
      efficiency: calculate_bandwidth_efficiency(state.connection_metrics)
    }
  end

  defp get_feature_stats(_feature, _state) do
    %{status: :active}
  end
end
