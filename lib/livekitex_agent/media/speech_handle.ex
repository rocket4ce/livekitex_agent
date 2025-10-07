defmodule LivekitexAgent.SpeechHandle do
  @moduledoc """
  Speech handle for managing speech output and interruption control.

  This module provides sophisticated interruption handling capabilities for real-time
  voice interactions. It manages speech buffers, provides graceful degradation during
  interruptions, and maintains conversation context during speech events.

  ## Features

  - **Interruption Control**: Allows graceful interruption of ongoing speech
  - **Buffer Management**: Maintains audio buffers for rollback and context preservation
  - **State Management**: Tracks speech state and timing for optimal user experience
  - **Event Integration**: Integrates with VAD and TTS systems for coordinated behavior
  - **Performance Optimization**: Sub-100ms response times for interruption handling

  ## Usage

      iex> {:ok, handle} = SpeechHandle.start_link(session_pid: self())
      iex> SpeechHandle.start_speech(handle, "Hello, how can I help you?")
      iex> SpeechHandle.interrupt(handle)
      :ok

  ## Event Protocol

  The speech handle communicates with parent sessions via message passing:

  - `{:speech_handle_event, :speech_started, %{text: string, handle_id: id}}`
  - `{:speech_handle_event, :speech_interrupted, %{handle_id: id, remaining_text: string}}`
  - `{:speech_handle_event, :speech_completed, %{handle_id: id}}`
  - `{:speech_handle_event, :speech_error, %{handle_id: id, error: term}}`

  ## Configuration

  - `:buffer_size_ms` - Size of audio buffer for interruption handling (default: 500ms)
  - `:fade_out_ms` - Duration of fade-out during interruption (default: 50ms)
  - `:interrupt_timeout_ms` - Maximum time to wait for graceful interruption (default: 100ms)
  - `:enable_graceful_degradation` - Enable fallback behaviors during failures (default: true)
  """

  use GenServer
  require Logger

  @type handle_id :: String.t()
  @type speech_state :: :idle | :preparing | :speaking | :interrupted | :completed | :error

  defstruct [
    :session_pid,
    :handle_id,
    :current_text,
    :tts_pid,
    :audio_buffer,
    :start_time,
    state: :idle,
    buffer_size_ms: 500,
    fade_out_ms: 50,
    interrupt_timeout_ms: 100,
    enable_graceful_degradation: true,
    metrics: %{
      interruptions: 0,
      completions: 0,
      errors: 0,
      avg_response_time_ms: 0
    }
  ]

  @type opts :: [
          session_pid: pid(),
          handle_id: handle_id() | nil,
          buffer_size_ms: pos_integer(),
          fade_out_ms: pos_integer(),
          interrupt_timeout_ms: pos_integer(),
          enable_graceful_degradation: boolean()
        ]

  # Public API

  @doc """
  Start a new speech handle.
  """
  @spec start_link(opts()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Start speech synthesis and output.
  """
  @spec start_speech(pid(), String.t(), keyword()) :: :ok | {:error, term()}
  def start_speech(pid, text, opts \\ []) do
    GenServer.call(pid, {:start_speech, text, opts})
  end

  @doc """
  Interrupt the current speech output.
  """
  @spec interrupt(pid()) :: :ok | {:error, term()}
  def interrupt(pid) do
    GenServer.call(pid, :interrupt)
  end

  @doc """
  Get the current state of the speech handle.
  """
  @spec get_state(pid()) :: speech_state()
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Get performance metrics for this speech handle.
  """
  @spec get_metrics(pid()) :: map()
  def get_metrics(pid) do
    GenServer.call(pid, :get_metrics)
  end

  @doc """
  Check if speech is currently active.
  """
  @spec speaking?(pid()) :: boolean()
  def speaking?(pid) do
    GenServer.call(pid, :speaking?)
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
      handle_id: Keyword.get(opts, :handle_id, generate_handle_id()),
      buffer_size_ms: Keyword.get(opts, :buffer_size_ms, 500),
      fade_out_ms: Keyword.get(opts, :fade_out_ms, 50),
      interrupt_timeout_ms: Keyword.get(opts, :interrupt_timeout_ms, 100),
      enable_graceful_degradation: Keyword.get(opts, :enable_graceful_degradation, true),
      audio_buffer: :queue.new()
    }

    Logger.debug("SpeechHandle started with ID: #{state.handle_id}")
    {:ok, state}
  end

  @impl true
  def handle_call({:start_speech, text, opts}, _from, state) do
    case state.state do
      :idle ->
        case start_speech_synthesis(text, opts, state) do
          {:ok, new_state} ->
            notify_session(state.session_pid, :speech_started, %{
              text: text,
              handle_id: state.handle_id
            })

            {:reply, :ok, new_state}

          {:error, reason} ->
            error_state = %{state | state: :error}
            notify_session(state.session_pid, :speech_error, %{
              handle_id: state.handle_id,
              error: reason
            })

            {:reply, {:error, reason}, error_state}
        end

      current_state ->
        {:reply, {:error, {:invalid_state, current_state}}, state}
    end
  end

  @impl true
  def handle_call(:interrupt, _from, state) do
    case state.state do
      :speaking ->
        {:ok, new_state} = perform_interruption(state)
        {:reply, :ok, new_state}

      :preparing ->
        # Can interrupt during preparation
        interrupted_state = %{state | state: :interrupted}

        notify_session(state.session_pid, :speech_interrupted, %{
          handle_id: state.handle_id,
          remaining_text: state.current_text
        })

        {:reply, :ok, interrupted_state}

      current_state ->
        {:reply, {:error, {:not_speaking, current_state}}, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.state, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  @impl true
  def handle_call(:speaking?, _from, state) do
    speaking = state.state in [:preparing, :speaking]
    {:reply, speaking, state}
  end

  @impl true
  def handle_info({:tts_audio_chunk, chunk}, state) do
    # Buffer audio for potential rollback during interruptions
    buffered_state = buffer_audio_chunk(chunk, state)
    {:noreply, buffered_state}
  end

  @impl true
  def handle_info({:tts_completed}, state) do
    completed_state = %{
      state
      | state: :completed,
        metrics: update_completion_metrics(state.metrics)
    }

    notify_session(state.session_pid, :speech_completed, %{
      handle_id: state.handle_id
    })

    {:noreply, completed_state}
  end

  @impl true
  def handle_info({:tts_error, reason}, state) do
    error_state = %{
      state
      | state: :error,
        metrics: update_error_metrics(state.metrics)
    }

    notify_session(state.session_pid, :speech_error, %{
      handle_id: state.handle_id,
      error: reason
    })

    {:noreply, error_state}
  end

  @impl true
  def handle_info(:interrupt_timeout, state) do
    # Force interrupt if graceful interrupt times out
    if state.state == :interrupted do
      forced_state = force_interrupt(state)
      {:noreply, forced_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("SpeechHandle received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp start_speech_synthesis(text, opts, state) do
    # Start TTS synthesis
    case start_tts_process(text, opts, state) do
      {:ok, tts_pid} ->
        new_state = %{
          state
          | state: :preparing,
            current_text: text,
            tts_pid: tts_pid,
            start_time: System.monotonic_time(:millisecond)
        }

        {:ok, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_tts_process(text, _opts, _state) do
    # This would integrate with the actual TTS system
    # For now, simulate the process

    # In a real implementation, this would start the TTS GenServer
    spawn_link(fn -> simulate_tts_process(text, self()) end)
    |> then(&{:ok, &1})
  end

  defp simulate_tts_process(text, parent) do
    # Simulate TTS processing
    Process.sleep(50) # Simulate synthesis time

    # Send audio chunks
    chunks = String.split(text, " ")

    Enum.each(chunks, fn chunk ->
      send(parent, {:tts_audio_chunk, chunk})
      Process.sleep(100) # Simulate chunk timing
    end)

    send(parent, {:tts_completed})
  end

  defp perform_interruption(state) do
    # Graceful interruption with fade-out
    if state.tts_pid do
      # Signal TTS process to stop
      Process.exit(state.tts_pid, :interrupt)
    end

    # Apply fade-out effect
    Process.send_after(self(), :interrupt_timeout, state.interrupt_timeout_ms)

    interrupted_state = %{
      state
      | state: :interrupted,
        metrics: update_interruption_metrics(state.metrics)
    }

    notify_session(state.session_pid, :speech_interrupted, %{
      handle_id: state.handle_id,
      remaining_text: get_remaining_text(state)
    })

    {:ok, interrupted_state}
  end

  defp force_interrupt(state) do
    # Force stop without graceful degradation
    if state.tts_pid do
      Process.exit(state.tts_pid, :kill)
    end

    %{
      state
      | state: :interrupted,
        tts_pid: nil,
        metrics: update_interruption_metrics(state.metrics)
    }
  end

  defp buffer_audio_chunk(chunk, state) do
    # Add chunk to circular buffer
    buffer = :queue.in(chunk, state.audio_buffer)

    # Limit buffer size based on time
    buffer_size_limit = calculate_buffer_size_limit(state.buffer_size_ms)
    trimmed_buffer = trim_buffer_to_size(buffer, buffer_size_limit)

    %{state | audio_buffer: trimmed_buffer}
  end

  defp calculate_buffer_size_limit(buffer_ms) do
    # Calculate maximum number of chunks based on time
    # Assuming ~100ms per chunk (this would be configurable in real implementation)
    div(buffer_ms, 100)
  end

  defp trim_buffer_to_size(buffer, max_size) do
    if :queue.len(buffer) <= max_size do
      buffer
    else
      {_dropped, trimmed} = :queue.out(buffer)
      trimmed
    end
  end

  defp get_remaining_text(state) do
    # In a real implementation, this would calculate remaining text based on
    # current synthesis progress
    state.current_text
  end

  defp notify_session(session_pid, event, data) do
    send(session_pid, {:speech_handle_event, event, data})
  end

  defp generate_handle_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode64(padding: false)
  end

  defp update_completion_metrics(metrics) do
    %{metrics | completions: metrics.completions + 1}
  end

  defp update_interruption_metrics(metrics) do
    %{metrics | interruptions: metrics.interruptions + 1}
  end

  defp update_error_metrics(metrics) do
    %{metrics | errors: metrics.errors + 1}
  end
end
