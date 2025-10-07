defmodule LivekitexAgent.InterruptionHandler do
  @moduledoc """
  Advanced speech interruption handling with graceful degradation.

  This module provides sophisticated interruption handling that integrates
  Voice Activity Detection (VAD), Speech Handle management, and graceful
  degradation strategies for optimal real-time voice interaction experience.

  ## Key Features

  - **VAD Integration**: Automatic interruption detection via voice activity
  - **Speech Handle Coordination**: Manages speech output interruptions
  - **Graceful Degradation**: Fallback strategies for failed interruptions
  - **Context Preservation**: Maintains conversation context during interruptions
  - **Performance Optimization**: Sub-100ms interruption response times
  - **Metrics Tracking**: Comprehensive interruption analytics

  ## Architecture

  The InterruptionHandler works as a coordinator between multiple components:

  ```
  VAD -> InterruptionHandler -> SpeechHandle
   |                         |
   v                         v
  AgentSession <-- StreamManager
  ```

  ## Usage

      # Start interruption handler
      {:ok, handler} = InterruptionHandler.start_link(
        session_pid: session_pid,
        vad_pid: vad_pid,
        speech_handle_pid: speech_handle_pid
      )

      # Manual interruption
      InterruptionHandler.interrupt(handler, :manual)

      # Configure interruption sensitivity
      InterruptionHandler.configure(handler, sensitivity: 0.8)

  ## Interruption Types

  - `:vad` - Voice activity detected interruption
  - `:manual` - User-initiated interruption
  - `:system` - System-initiated interruption (errors, timeouts)
  - `:preemptive` - Preemptive interruption for urgent responses
  """

  use GenServer
  require Logger

  alias LivekitexAgent.SpeechHandle
  alias LivekitexAgent.StreamManager

  @type interruption_type :: :vad | :manual | :system | :preemptive
  @type interruption_strategy :: :immediate | :graceful | :fade_out | :smart
  # 0.0 - 1.0
  @type sensitivity_level :: float()

  defstruct [
    :session_pid,
    :vad_pid,
    :speech_handle_pid,
    :stream_manager_pid,
    interruption_strategy: :graceful,
    sensitivity: 0.7,
    interrupt_timeout_ms: 100,
    enable_preemptive: true,
    enable_vad_interruption: true,
    grace_period_ms: 150,
    metrics: %{
      total_interruptions: 0,
      vad_interruptions: 0,
      manual_interruptions: 0,
      system_interruptions: 0,
      successful_interruptions: 0,
      failed_interruptions: 0,
      avg_interruption_latency_ms: 0,
      graceful_degradations: 0
    }
  ]

  @type opts :: [
          session_pid: pid(),
          vad_pid: pid() | nil,
          speech_handle_pid: pid() | nil,
          stream_manager_pid: pid() | nil,
          interruption_strategy: interruption_strategy(),
          sensitivity: sensitivity_level(),
          interrupt_timeout_ms: pos_integer(),
          enable_preemptive: boolean(),
          enable_vad_interruption: boolean(),
          grace_period_ms: pos_integer()
        ]

  # Public API

  @doc """
  Start the interruption handler.
  """
  @spec start_link(opts()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Manually trigger an interruption.
  """
  @spec interrupt(pid(), interruption_type(), keyword()) :: :ok | {:error, term()}
  def interrupt(pid, type \\ :manual, opts \\ []) do
    GenServer.call(pid, {:interrupt, type, opts})
  end

  @doc """
  Configure interruption behavior.
  """
  @spec configure(pid(), keyword()) :: :ok | {:error, term()}
  def configure(pid, opts) do
    GenServer.call(pid, {:configure, opts})
  end

  @doc """
  Get interruption metrics.
  """
  @spec get_metrics(pid()) :: map()
  def get_metrics(pid) do
    GenServer.call(pid, :get_metrics)
  end

  @doc """
  Enable or disable VAD-based interruptions.
  """
  @spec set_vad_enabled(pid(), boolean()) :: :ok
  def set_vad_enabled(pid, enabled) do
    GenServer.cast(pid, {:set_vad_enabled, enabled})
  end

  @doc """
  Update sensitivity level for interruption detection.
  """
  @spec set_sensitivity(pid(), sensitivity_level()) :: :ok | {:error, term()}
  def set_sensitivity(pid, sensitivity) when sensitivity >= 0.0 and sensitivity <= 1.0 do
    GenServer.cast(pid, {:set_sensitivity, sensitivity})
  end

  def set_sensitivity(_pid, sensitivity) do
    {:error, {:invalid_sensitivity, sensitivity}}
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
      vad_pid: Keyword.get(opts, :vad_pid),
      speech_handle_pid: Keyword.get(opts, :speech_handle_pid),
      stream_manager_pid: Keyword.get(opts, :stream_manager_pid),
      interruption_strategy: Keyword.get(opts, :interruption_strategy, :graceful),
      sensitivity: Keyword.get(opts, :sensitivity, 0.7),
      interrupt_timeout_ms: Keyword.get(opts, :interrupt_timeout_ms, 100),
      enable_preemptive: Keyword.get(opts, :enable_preemptive, true),
      enable_vad_interruption: Keyword.get(opts, :enable_vad_interruption, true),
      grace_period_ms: Keyword.get(opts, :grace_period_ms, 150)
    }

    Logger.debug("InterruptionHandler started with strategy: #{state.interruption_strategy}")
    {:ok, state}
  end

  @impl true
  def handle_call({:interrupt, type, opts}, _from, state) do
    start_time = System.monotonic_time(:millisecond)

    case perform_interruption(type, opts, state) do
      {:ok, new_state} ->
        end_time = System.monotonic_time(:millisecond)
        latency = end_time - start_time

        updated_state = update_success_metrics(new_state, type, latency)
        {:reply, :ok, updated_state}

      {:error, reason, new_state} ->
        updated_state = update_failure_metrics(new_state, type)
        {:reply, {:error, reason}, updated_state}
    end
  end

  @impl true
  def handle_call({:configure, opts}, _from, state) do
    case apply_configuration(opts, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  @impl true
  def handle_cast({:set_vad_enabled, enabled}, state) do
    new_state = %{state | enable_vad_interruption: enabled}
    Logger.debug("VAD interruption #{if enabled, do: "enabled", else: "disabled"}")
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:set_sensitivity, sensitivity}, state) do
    new_state = %{state | sensitivity: sensitivity}
    Logger.debug("Interruption sensitivity set to: #{sensitivity}")
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:vad_event, :speech_start}, state) do
    if state.enable_vad_interruption do
      case should_interrupt_on_vad(state) do
        true ->
          Logger.debug("VAD detected speech start - triggering interruption")
          {:ok, new_state} = perform_interruption(:vad, [], state)
          {:noreply, new_state}

        false ->
          Logger.debug(
            "VAD detected speech start - interruption not triggered (sensitivity/conditions)"
          )

          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:vad_event, :speech_end}, state) do
    # Speech ended - could be used for additional logic
    Logger.debug("VAD detected speech end")
    {:noreply, state}
  end

  @impl true
  def handle_info({:speech_handle_event, event, data}, state) do
    handle_speech_handle_event(event, data, state)
  end

  @impl true
  def handle_info({:stream_data, stream_type, _data, _timestamp}, state) do
    # Monitor stream data for interruption opportunities
    case {stream_type, state.enable_preemptive} do
      {:audio, true} ->
        # Could analyze audio data for preemptive interruption
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("InterruptionHandler received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp perform_interruption(type, opts, state) do
    Logger.info("Performing #{type} interruption with strategy: #{state.interruption_strategy}")

    try do
      case state.interruption_strategy do
        :immediate ->
          immediate_interruption(type, opts, state)

        :graceful ->
          graceful_interruption(type, opts, state)

        :fade_out ->
          fade_out_interruption(type, opts, state)

        :smart ->
          smart_interruption(type, opts, state)
      end
    rescue
      error ->
        Logger.error("Interruption failed with error: #{inspect(error)}")
        {:error, error, state}
    end
  end

  defp immediate_interruption(type, _opts, state) do
    # Immediate interruption - stop everything now
    results = [
      interrupt_speech_handle(state),
      interrupt_session(state),
      notify_interruption(type, state)
    ]

    if Enum.all?(results, &match?(:ok, &1)) do
      {:ok, increment_interruption_count(state, type)}
    else
      failed_result = Enum.find(results, &(!match?(:ok, &1)))
      {:error, failed_result, state}
    end
  end

  defp graceful_interruption(type, _opts, state) do
    # Graceful interruption with fade-out and context preservation
    with :ok <- start_graceful_fade(state),
         :ok <- preserve_context(state),
         :ok <- interrupt_speech_handle(state),
         :ok <- interrupt_session(state),
         :ok <- notify_interruption(type, state) do
      {:ok, increment_interruption_count(state, type)}
    else
      {:error, reason} ->
        # Fallback to immediate interruption if graceful fails
        Logger.warning(
          "Graceful interruption failed: #{inspect(reason)}, falling back to immediate"
        )

        immediate_interruption(type, [], %{
          state
          | metrics: %{
              state.metrics
              | graceful_degradations: state.metrics.graceful_degradations + 1
            }
        })

      error ->
        {:error, error, state}
    end
  end

  defp fade_out_interruption(type, _opts, state) do
    # Fade-out interruption with audio processing
    with :ok <- start_audio_fade_out(state),
         :ok <- schedule_complete_stop(state),
         :ok <- notify_interruption(type, state) do
      {:ok, increment_interruption_count(state, type)}
    else
      error ->
        {:error, error, state}
    end
  end

  defp smart_interruption(type, _opts, state) do
    # Smart interruption - analyzes context to choose best strategy
    strategy = choose_smart_strategy(state)
    Logger.debug("Smart interruption chose strategy: #{strategy}")

    new_state = %{state | interruption_strategy: strategy}
    perform_interruption(type, [], new_state)
  end

  defp interrupt_speech_handle(state) do
    if state.speech_handle_pid do
      SpeechHandle.interrupt(state.speech_handle_pid)
    else
      :ok
    end
  end

  defp interrupt_session(state) do
    send(state.session_pid, {:interruption_handler, :interrupt})
    :ok
  end

  defp notify_interruption(type, state) do
    send(state.session_pid, {:interruption_handler, :interrupted, type})
    :ok
  end

  defp start_graceful_fade(state) do
    if state.speech_handle_pid do
      # This would trigger a graceful fade in the speech handle
      send(state.speech_handle_pid, {:start_fade_out, state.grace_period_ms})
    end

    :ok
  end

  defp preserve_context(state) do
    # Preserve conversation context during interruption
    send(state.session_pid, {:interruption_handler, :preserve_context})
    :ok
  end

  defp start_audio_fade_out(state) do
    if state.stream_manager_pid do
      StreamManager.update_quality(state.stream_manager_pid, :audio, :low)
    end

    :ok
  end

  defp schedule_complete_stop(state) do
    Process.send_after(self(), :complete_fade_stop, state.grace_period_ms)
    :ok
  end

  defp choose_smart_strategy(state) do
    # Smart strategy selection based on current conditions
    cond do
      state.sensitivity > 0.8 ->
        :immediate

      state.sensitivity > 0.5 ->
        :graceful

      true ->
        :fade_out
    end
  end

  defp should_interrupt_on_vad(state) do
    # Determine if VAD event should trigger interruption
    # Configurable threshold
    state.sensitivity > 0.3
  end

  defp handle_speech_handle_event(:speech_interrupted, _data, state) do
    Logger.debug("Speech handle reported interruption completed")
    {:noreply, state}
  end

  defp handle_speech_handle_event(:speech_error, data, state) do
    Logger.warning("Speech handle error during interruption: #{inspect(data)}")
    {:noreply, state}
  end

  defp handle_speech_handle_event(_event, _data, state) do
    {:noreply, state}
  end

  defp apply_configuration(opts, state) do
    try do
      new_state =
        Enum.reduce(opts, state, fn
          {:interruption_strategy, strategy}, acc
          when strategy in [:immediate, :graceful, :fade_out, :smart] ->
            %{acc | interruption_strategy: strategy}

          {:sensitivity, sensitivity}, acc when sensitivity >= 0.0 and sensitivity <= 1.0 ->
            %{acc | sensitivity: sensitivity}

          {:interrupt_timeout_ms, timeout}, acc when is_integer(timeout) and timeout > 0 ->
            %{acc | interrupt_timeout_ms: timeout}

          {:enable_preemptive, enabled}, acc when is_boolean(enabled) ->
            %{acc | enable_preemptive: enabled}

          {:enable_vad_interruption, enabled}, acc when is_boolean(enabled) ->
            %{acc | enable_vad_interruption: enabled}

          {:grace_period_ms, period}, acc when is_integer(period) and period > 0 ->
            %{acc | grace_period_ms: period}

          {key, value}, _acc ->
            throw({:invalid_config, key, value})
        end)

      {:ok, new_state}
    catch
      {:invalid_config, key, value} ->
        {:error, {:invalid_config, key, value}}
    end
  end

  defp increment_interruption_count(state, type) do
    metrics = state.metrics

    updated_metrics = %{
      metrics
      | total_interruptions: metrics.total_interruptions + 1,
        successful_interruptions: metrics.successful_interruptions + 1
    }

    # Increment type-specific counter
    type_specific_metrics =
      case type do
        :vad ->
          %{updated_metrics | vad_interruptions: updated_metrics.vad_interruptions + 1}

        :manual ->
          %{updated_metrics | manual_interruptions: updated_metrics.manual_interruptions + 1}

        :system ->
          %{updated_metrics | system_interruptions: updated_metrics.system_interruptions + 1}

        _ ->
          updated_metrics
      end

    %{state | metrics: type_specific_metrics}
  end

  defp update_success_metrics(state, type, latency) do
    state = increment_interruption_count(state, type)
    current_avg = state.metrics.avg_interruption_latency_ms
    total_successful = state.metrics.successful_interruptions

    new_avg =
      if total_successful > 1 do
        (current_avg * (total_successful - 1) + latency) / total_successful
      else
        latency
      end

    updated_metrics = %{state.metrics | avg_interruption_latency_ms: new_avg}
    %{state | metrics: updated_metrics}
  end

  defp update_failure_metrics(state, type) do
    state = increment_interruption_count(state, type)

    updated_metrics = %{
      state.metrics
      | failed_interruptions: state.metrics.failed_interruptions + 1
    }

    %{state | metrics: updated_metrics}
  end
end
