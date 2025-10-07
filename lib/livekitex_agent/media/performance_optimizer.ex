defmodule LivekitexAgent.Media.PerformanceOptimizer do
  @moduledoc """
  Performance optimization module for sub-100ms audio processing latency.

  This module provides advanced optimization techniques for real-time audio processing
  to ensure consistent sub-100ms latency performance across all components of the
  voice agent pipeline.

  ## Optimization Areas

  - **Buffer Management**: Dynamic buffer sizing based on system performance
  - **Processing Pipeline**: Optimized audio processing algorithms
  - **Memory Management**: Efficient memory allocation and garbage collection
  - **CPU Scheduling**: Process priority optimization for real-time performance
  - **Network Optimization**: WebRTC and network-level optimizations
  - **System Tuning**: OS-level optimizations for audio processing

  ## Key Metrics

  - Target latency: < 100ms end-to-end
  - Processing latency: < 20ms per stage
  - Buffer latency: < 50ms
  - Network latency: < 30ms
  - Jitter: < 10ms standard deviation

  ## Usage

      # Start the optimizer for a session
      {:ok, optimizer} = PerformanceOptimizer.start_link(
        audio_processor: audio_pid,
        stream_manager: stream_pid,
        target_latency_ms: 80
      )

      # Apply optimizations
      PerformanceOptimizer.optimize_for_realtime(optimizer)

      # Monitor performance
      metrics = PerformanceOptimizer.get_performance_metrics(optimizer)
  """

  use GenServer
  require Logger

  alias LivekitexAgent.Media.AudioProcessor
  alias LivekitexAgent.StreamManager

  @target_latency_ms 100
  @critical_latency_ms 150
  @optimization_check_interval_ms 500

  defstruct [
    :audio_processor,
    :stream_manager,
    :session_pid,
    target_latency_ms: @target_latency_ms,
    current_metrics: %{},
    optimization_history: [],
    active_optimizations: [],
    performance_profile: :balanced,
    monitor_ref: nil
  ]

  @type performance_profile :: :realtime | :balanced | :quality | :battery_saver
  @type optimization_type :: :buffer_size | :process_priority | :gc_tuning | :network_optimization

  @type opts :: [
          audio_processor: pid() | nil,
          stream_manager: pid() | nil,
          session_pid: pid() | nil,
          target_latency_ms: pos_integer(),
          performance_profile: performance_profile()
        ]

  # Public API

  @doc """
  Start the performance optimizer.
  """
  @spec start_link(opts()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Apply real-time optimizations.
  """
  @spec optimize_for_realtime(pid()) :: :ok | {:error, term()}
  def optimize_for_realtime(pid) do
    GenServer.call(pid, :optimize_for_realtime)
  end

  @doc """
  Get current performance metrics.
  """
  @spec get_performance_metrics(pid()) :: map()
  def get_performance_metrics(pid) do
    GenServer.call(pid, :get_performance_metrics)
  end

  @doc """
  Set performance profile.
  """
  @spec set_performance_profile(pid(), performance_profile()) :: :ok
  def set_performance_profile(pid, profile) do
    GenServer.cast(pid, {:set_performance_profile, profile})
  end

  @doc """
  Trigger immediate optimization check.
  """
  @spec check_and_optimize(pid()) :: :ok
  def check_and_optimize(pid) do
    GenServer.cast(pid, :check_and_optimize)
  end

  # GenServer Implementation

  @impl true
  def init(opts) do
    state = %__MODULE__{
      audio_processor: Keyword.get(opts, :audio_processor),
      stream_manager: Keyword.get(opts, :stream_manager),
      session_pid: Keyword.get(opts, :session_pid),
      target_latency_ms: Keyword.get(opts, :target_latency_ms, @target_latency_ms),
      performance_profile: Keyword.get(opts, :performance_profile, :balanced)
    }

    # Start periodic performance monitoring
    monitor_ref =
      :timer.send_interval(@optimization_check_interval_ms, self(), :performance_check)

    Logger.info("PerformanceOptimizer started with target latency: #{state.target_latency_ms}ms")

    {:ok, %{state | monitor_ref: monitor_ref}}
  end

  @impl true
  def handle_call(:optimize_for_realtime, _from, state) do
    Logger.info("Applying real-time optimizations")

    optimizations = [
      :reduce_buffer_sizes,
      :increase_process_priority,
      :optimize_gc_settings,
      :enable_network_optimizations,
      :minimize_memory_allocation
    ]

    case apply_optimizations(optimizations, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_performance_metrics, _from, state) do
    metrics = collect_current_metrics(state)
    {:reply, metrics, %{state | current_metrics: metrics}}
  end

  @impl true
  def handle_cast({:set_performance_profile, profile}, state) do
    Logger.info("Setting performance profile to: #{profile}")

    new_state = %{state | performance_profile: profile}
    optimized_state = apply_profile_optimizations(profile, new_state)

    {:noreply, optimized_state}
  end

  @impl true
  def handle_cast(:check_and_optimize, state) do
    new_state = perform_optimization_check(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:performance_check, state) do
    new_state = perform_optimization_check(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("PerformanceOptimizer received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp apply_optimizations(optimizations, state) do
    try do
      new_state =
        Enum.reduce(optimizations, state, fn opt, acc_state ->
          apply_optimization(opt, acc_state)
        end)

      {:ok, new_state}
    rescue
      error ->
        Logger.error("Optimization failed: #{inspect(error)}")
        {:error, error}
    end
  end

  defp apply_optimization(:reduce_buffer_sizes, state) do
    # Reduce buffer sizes for lower latency
    if state.audio_processor do
      send(state.audio_processor, {:optimize_buffers, :low_latency})
    end

    if state.stream_manager do
      # Configure stream manager for low latency (would need to implement this method)
      send(state.stream_manager, {:configure, buffer_size_ms: 50})
    end

    record_optimization(:reduce_buffer_sizes, state)
  end

  defp apply_optimization(:increase_process_priority, state) do
    # Increase process priority for real-time performance
    try do
      if state.audio_processor do
        Process.flag(state.audio_processor, :priority, :high)
      end

      if state.stream_manager do
        Process.flag(state.stream_manager, :priority, :high)
      end

      # Set own priority to high as well
      Process.flag(self(), :priority, :high)

      Logger.debug("Process priorities increased for real-time performance")
    rescue
      error ->
        Logger.warning("Failed to increase process priority: #{inspect(error)}")
    end

    record_optimization(:increase_process_priority, state)
  end

  defp apply_optimization(:optimize_gc_settings, state) do
    # Optimize garbage collection for lower latency
    try do
      # Reduce GC frequency but make it more aggressive when it runs
      :erlang.system_flag(:schedulers_online, :erlang.system_info(:logical_processors))

      # Configure for low-latency GC
      pids_to_optimize = [
        state.audio_processor,
        state.stream_manager,
        state.session_pid,
        self()
      ]

      Enum.each(pids_to_optimize, fn pid ->
        if pid && Process.alive?(pid) do
          # Larger initial heap
          Process.flag(pid, :min_heap_size, 4096)
          # Larger binary heap
          Process.flag(pid, :min_bin_vheap_size, 4096)
        end
      end)

      Logger.debug("GC settings optimized for low latency")
    rescue
      error ->
        Logger.warning("Failed to optimize GC settings: #{inspect(error)}")
    end

    record_optimization(:optimize_gc_settings, state)
  end

  defp apply_optimization(:enable_network_optimizations, state) do
    # Network-level optimizations for WebRTC
    try do
      # These would integrate with the actual LiveKit/WebRTC implementation
      if state.session_pid do
        send(state.session_pid, {:network_optimization, :enable_low_latency})
      end

      Logger.debug("Network optimizations enabled")
    rescue
      error ->
        Logger.warning("Failed to enable network optimizations: #{inspect(error)}")
    end

    record_optimization(:enable_network_optimizations, state)
  end

  defp apply_optimization(:minimize_memory_allocation, state) do
    # Minimize memory allocations during audio processing
    if state.audio_processor do
      send(state.audio_processor, {:memory_optimization, :minimize_allocations})
    end

    record_optimization(:minimize_memory_allocation, state)
  end

  defp apply_optimization(unknown_opt, state) do
    Logger.warning("Unknown optimization: #{inspect(unknown_opt)}")
    state
  end

  defp apply_profile_optimizations(:realtime, state) do
    # Maximum performance, minimum latency
    optimizations = [
      :reduce_buffer_sizes,
      :increase_process_priority,
      :optimize_gc_settings,
      :enable_network_optimizations,
      :minimize_memory_allocation
    ]

    case apply_optimizations(optimizations, state) do
      {:ok, new_state} -> new_state
      {:error, _} -> state
    end
  end

  defp apply_profile_optimizations(:balanced, state) do
    # Balance between performance and resource usage
    optimizations = [
      :increase_process_priority,
      :optimize_gc_settings
    ]

    case apply_optimizations(optimizations, state) do
      {:ok, new_state} -> new_state
      {:error, _} -> state
    end
  end

  defp apply_profile_optimizations(:quality, state) do
    # Prioritize quality over latency
    if state.audio_processor do
      send(state.audio_processor, {:optimize_buffers, :quality})
    end

    state
  end

  defp apply_profile_optimizations(:battery_saver, state) do
    # Minimize resource usage
    if state.audio_processor do
      send(state.audio_processor, {:optimize_buffers, :battery_saver})
    end

    state
  end

  defp perform_optimization_check(state) do
    current_metrics = collect_current_metrics(state)

    # Check if current performance meets targets
    case analyze_performance(current_metrics, state) do
      {:needs_optimization, issues} ->
        Logger.info("Performance issues detected: #{inspect(issues)}")
        apply_corrective_optimizations(issues, state)

      {:performance_good} ->
        Logger.debug("Performance within targets")
        %{state | current_metrics: current_metrics}

      {:performance_critical, issues} ->
        Logger.warning("Critical performance issues: #{inspect(issues)}")
        apply_emergency_optimizations(issues, state)
    end
  end

  defp collect_current_metrics(state) do
    base_metrics = %{
      timestamp: System.monotonic_time(:millisecond),
      target_latency_ms: state.target_latency_ms
    }

    # Collect audio processor metrics
    audio_metrics =
      if state.audio_processor do
        try do
          AudioProcessor.get_latency_metrics()
        rescue
          _ -> %{audio_latency_ms: nil, error: :audio_processor_unavailable}
        end
      else
        %{audio_latency_ms: nil, error: :no_audio_processor}
      end

    # Collect stream manager metrics
    stream_metrics =
      if state.stream_manager do
        try do
          StreamManager.get_metrics(state.stream_manager)
        rescue
          _ -> %{stream_latency_ms: nil, error: :stream_manager_unavailable}
        end
      else
        %{stream_latency_ms: nil, error: :no_stream_manager}
      end

    # System metrics
    system_metrics = %{
      memory_usage: :erlang.memory(:total),
      process_count: :erlang.system_info(:process_count),
      scheduler_utilization: get_scheduler_utilization()
    }

    Map.merge(base_metrics, %{
      audio: audio_metrics,
      stream: stream_metrics,
      system: system_metrics
    })
  end

  defp get_scheduler_utilization do
    try do
      # Use alternative approach since scheduler module functions are not available
      # Get approximate utilization from system info
      Process.sleep(100)

      # Estimate utilization based on process count and system load
      process_count = :erlang.system_info(:process_count)
      scheduler_count = :erlang.system_info(:schedulers_online)

      # Basic estimation (this is a placeholder)
      utilization = min(process_count / (scheduler_count * 1000), 1.0)
      utilization
    rescue
      _ -> 0.0
    end
  end

  defp analyze_performance(metrics, state) do
    issues = []

    # Check audio latency
    issues =
      case get_in(metrics, [:audio, :total_latency_ms]) do
        nil -> issues
        latency when latency > @critical_latency_ms -> [:critical_audio_latency | issues]
        latency when latency > state.target_latency_ms -> [:high_audio_latency | issues]
        _ -> issues
      end

    # Check memory usage
    issues =
      case get_in(metrics, [:system, :memory_usage]) do
        # 1GB
        memory when memory > 1_000_000_000 -> [:high_memory_usage | issues]
        _ -> issues
      end

    # Check scheduler utilization
    issues =
      case get_in(metrics, [:system, :scheduler_utilization]) do
        util when util > 0.8 -> [:high_cpu_usage | issues]
        _ -> issues
      end

    cond do
      Enum.any?(issues, &(&1 in [:critical_audio_latency])) ->
        {:performance_critical, issues}

      length(issues) > 0 ->
        {:needs_optimization, issues}

      true ->
        {:performance_good}
    end
  end

  defp apply_corrective_optimizations(issues, state) do
    optimizations = determine_optimizations_for_issues(issues)

    case apply_optimizations(optimizations, state) do
      {:ok, new_state} ->
        Logger.info("Applied corrective optimizations: #{inspect(optimizations)}")
        new_state

      {:error, reason} ->
        Logger.error("Failed to apply corrective optimizations: #{inspect(reason)}")
        state
    end
  end

  defp apply_emergency_optimizations(_issues, state) do
    # Apply more aggressive optimizations for critical performance issues
    emergency_optimizations = [
      :reduce_buffer_sizes,
      :increase_process_priority,
      :minimize_memory_allocation,
      :emergency_gc_cleanup
    ]

    case apply_optimizations(emergency_optimizations, state) do
      {:ok, new_state} ->
        Logger.warning("Applied emergency optimizations for critical performance issues")
        new_state

      {:error, reason} ->
        Logger.error("Failed to apply emergency optimizations: #{inspect(reason)}")
        state
    end
  end

  defp determine_optimizations_for_issues(issues) do
    optimizations = []

    optimizations =
      if :high_audio_latency in issues or :critical_audio_latency in issues do
        [:reduce_buffer_sizes, :increase_process_priority | optimizations]
      else
        optimizations
      end

    optimizations =
      if :high_memory_usage in issues do
        [:optimize_gc_settings, :minimize_memory_allocation | optimizations]
      else
        optimizations
      end

    optimizations =
      if :high_cpu_usage in issues do
        [:increase_process_priority | optimizations]
      else
        optimizations
      end

    Enum.uniq(optimizations)
  end

  defp record_optimization(optimization_type, state) do
    optimization_record = %{
      type: optimization_type,
      applied_at: System.monotonic_time(:millisecond),
      performance_profile: state.performance_profile
    }

    history = [optimization_record | state.optimization_history]
    active = [optimization_type | state.active_optimizations] |> Enum.uniq()

    %{state | optimization_history: history, active_optimizations: active}
  end
end
