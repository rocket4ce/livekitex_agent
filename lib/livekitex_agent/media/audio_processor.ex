defmodule LivekitexAgent.Media.AudioProcessor do
  @moduledoc """
  Base audio processing pipeline for real-time voice agent interactions.

  This module provides:
  - PCM16 audio format handling and conversion
  - Audio buffering and chunking for streaming
  - Sample rate conversion and audio preprocessing
  - Real-time audio pipeline management
  - Integration with LiveKit audio streams
  - Performance monitoring and optimization

  ## Audio Formats

  The pipeline primarily works with PCM16 format:
  - Sample rate: 16kHz, 24kHz, or 48kHz (configurable)
  - Channels: Mono (1 channel) or Stereo (2 channels)
  - Bit depth: 16-bit signed integers
  - Endianness: Little-endian

  ## Pipeline Stages

  1. **Input Processing**: Receive raw audio from LiveKit or local sources
  2. **Format Conversion**: Convert to standard PCM16 format
  3. **Buffering**: Manage audio chunks for streaming processing
  4. **Processing**: Apply audio transformations (filtering, normalization)
  5. **Output**: Send processed audio to providers or LiveKit
  """

  use GenServer
  require Logger
  use Bitwise

  @default_sample_rate 16_000
  @default_channels 1
  @default_chunk_duration_ms 100
  @default_buffer_size_ms 1000

  defstruct [
    :sample_rate,
    :channels,
    :chunk_duration_ms,
    :buffer_size_ms,
    :input_buffer,
    :output_buffer,
    :metrics,
    :callbacks,
    :processing_enabled
  ]

  @type audio_format :: %{
    sample_rate: pos_integer(),
    channels: pos_integer(),
    bit_depth: pos_integer(),
    format: :pcm16 | :pcm24 | :float32
  }

  @type audio_chunk :: %{
    data: binary(),
    format: audio_format(),
    timestamp: DateTime.t(),
    sequence: non_neg_integer()
  }

  @type processor_config :: %{
    sample_rate: pos_integer(),
    channels: pos_integer(),
    chunk_duration_ms: pos_integer(),
    buffer_size_ms: pos_integer(),
    enable_processing: boolean()
  }

  @type t :: %__MODULE__{
    sample_rate: pos_integer(),
    channels: pos_integer(),
    chunk_duration_ms: pos_integer(),
    buffer_size_ms: pos_integer(),
    input_buffer: :queue.queue(),
    output_buffer: :queue.queue(),
    metrics: map(),
    callbacks: map(),
    processing_enabled: boolean()
  }

  ## Client API

  @doc """
  Starts the audio processor GenServer.
  """
  def start_link(config \\ %{}) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Processes an incoming audio chunk.

  The audio chunk will be buffered, processed according to the pipeline
  configuration, and made available for consumption.
  """
  def process_input(audio_chunk) do
    GenServer.cast(__MODULE__, {:process_input, audio_chunk})
  end

  @doc """
  Gets the next processed audio chunk from the output buffer.
  """
  def get_output_chunk do
    GenServer.call(__MODULE__, :get_output_chunk)
  end

  @doc """
  Gets multiple output chunks up to the specified count.
  """
  def get_output_chunks(count \\ 10) do
    GenServer.call(__MODULE__, {:get_output_chunks, count})
  end

  @doc """
  Converts raw audio data to the standard PCM16 format.
  """
  def convert_to_pcm16(raw_data, source_format) do
    GenServer.call(__MODULE__, {:convert_to_pcm16, raw_data, source_format})
  end

  @doc """
  Registers a callback for audio processing events.

  Available events:
  - `:chunk_processed` - Called when an audio chunk is processed
  - `:buffer_overflow` - Called when input buffer overflows
  - `:processing_error` - Called when processing fails
  """
  def register_callback(event, callback) do
    GenServer.call(__MODULE__, {:register_callback, event, callback})
  end

  @doc """
  Gets current audio processing metrics.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Clears all buffered audio data.
  """
  def clear_buffers do
    GenServer.call(__MODULE__, :clear_buffers)
  end

  @doc """
  Updates the processor configuration.
  """
  def update_config(new_config) do
    GenServer.call(__MODULE__, {:update_config, new_config})
  end

  ## GenServer Callbacks

  @impl true
  def init(config) do
    state = %__MODULE__{
      sample_rate: Map.get(config, :sample_rate, @default_sample_rate),
      channels: Map.get(config, :channels, @default_channels),
      chunk_duration_ms: Map.get(config, :chunk_duration_ms, @default_chunk_duration_ms),
      buffer_size_ms: Map.get(config, :buffer_size_ms, @default_buffer_size_ms),
      input_buffer: :queue.new(),
      output_buffer: :queue.new(),
      metrics: init_metrics(),
      callbacks: %{},
      processing_enabled: Map.get(config, :enable_processing, true)
    }

    Logger.info("AudioProcessor started with config: #{inspect(config)}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:process_input, audio_chunk}, state) do
    start_time = System.monotonic_time(:microsecond)

    try do
      # Validate and convert audio chunk
      processed_chunk = process_audio_chunk(audio_chunk, state)

      # Add to input buffer
      new_input_buffer = :queue.in(processed_chunk, state.input_buffer)

      # Check buffer overflow
      {input_buffer, overflow_count} = manage_buffer_overflow(new_input_buffer, state)

      # Process audio if enabled
      {output_buffer, processed_count} = if state.processing_enabled do
        process_buffered_audio(input_buffer, state.output_buffer, state)
      else
        {state.output_buffer, 0}
      end

      # Update metrics
      processing_time = System.monotonic_time(:microsecond) - start_time
      new_metrics = update_processing_metrics(state.metrics, processing_time, processed_count, overflow_count)

      new_state = %{state |
        input_buffer: input_buffer,
        output_buffer: output_buffer,
        metrics: new_metrics
      }

      # Trigger callbacks
      trigger_callback(new_state, :chunk_processed, processed_chunk)
      if overflow_count > 0 do
        trigger_callback(new_state, :buffer_overflow, overflow_count)
      end

      {:noreply, new_state}

    rescue
      e ->
        Logger.error("Audio processing error: #{inspect(e)}")
        trigger_callback(state, :processing_error, e)
        {:noreply, update_error_metrics(state)}
    end
  end

  @impl true
  def handle_call(:get_output_chunk, _from, state) do
    case :queue.out(state.output_buffer) do
      {{:value, chunk}, new_buffer} ->
        new_state = %{state | output_buffer: new_buffer}
        {:reply, {:ok, chunk}, new_state}

      {:empty, _buffer} ->
        {:reply, {:error, :no_chunks_available}, state}
    end
  end

  @impl true
  def handle_call({:get_output_chunks, count}, _from, state) do
    {chunks, new_buffer} = extract_chunks(state.output_buffer, count, [])
    new_state = %{state | output_buffer: new_buffer}
    {:reply, chunks, new_state}
  end

  @impl true
  def handle_call({:convert_to_pcm16, raw_data, source_format}, _from, state) do
    try do
      converted_data = perform_format_conversion(raw_data, source_format, pcm16_format(state))
      {:reply, {:ok, converted_data}, state}
    rescue
      e ->
        {:reply, {:error, {:conversion_failed, e.message}}, state}
    end
  end

  @impl true
  def handle_call({:register_callback, event, callback}, _from, state) do
    new_callbacks = Map.put(state.callbacks, event, callback)
    new_state = %{state | callbacks: new_callbacks}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  @impl true
  def handle_call(:clear_buffers, _from, state) do
    new_state = %{state |
      input_buffer: :queue.new(),
      output_buffer: :queue.new()
    }
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:update_config, new_config}, _from, state) do
    new_state = %{state |
      sample_rate: Map.get(new_config, :sample_rate, state.sample_rate),
      channels: Map.get(new_config, :channels, state.channels),
      chunk_duration_ms: Map.get(new_config, :chunk_duration_ms, state.chunk_duration_ms),
      buffer_size_ms: Map.get(new_config, :buffer_size_ms, state.buffer_size_ms),
      processing_enabled: Map.get(new_config, :enable_processing, state.processing_enabled)
    }

    Logger.info("AudioProcessor config updated")
    {:reply, :ok, new_state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("AudioProcessor terminating with reason: #{inspect(reason)}")
    :ok
  end

  ## Private Functions

  defp init_metrics do
    %{
      chunks_processed: 0,
      total_processing_time_us: 0,
      average_processing_time_us: 0.0,
      buffer_overflows: 0,
      conversion_errors: 0,
      last_activity: DateTime.utc_now()
    }
  end

  defp process_audio_chunk(audio_chunk, state) do
    # Ensure chunk is in the correct format
    target_format = %{
      sample_rate: state.sample_rate,
      channels: state.channels,
      bit_depth: 16,
      format: :pcm16
    }

    if audio_chunk.format == target_format do
      audio_chunk
    else
      converted_data = perform_format_conversion(
        audio_chunk.data,
        audio_chunk.format,
        target_format
      )

      %{audio_chunk |
        data: converted_data,
        format: target_format
      }
    end
  end

  defp manage_buffer_overflow(buffer, state) do
    max_buffer_size = calculate_max_buffer_size(state)
    current_size = :queue.len(buffer)

    if current_size > max_buffer_size do
      overflow_count = current_size - max_buffer_size
      trimmed_buffer = trim_buffer(buffer, max_buffer_size)
      {trimmed_buffer, overflow_count}
    else
      {buffer, 0}
    end
  end

  defp calculate_max_buffer_size(state) do
    # Calculate maximum buffer size based on duration and chunk size
    max_chunks = (state.buffer_size_ms / state.chunk_duration_ms) |> round()
    max(max_chunks, 1)
  end

  defp trim_buffer(buffer, max_size) do
    current_size = :queue.len(buffer)
    excess = current_size - max_size

    Enum.reduce(1..excess, buffer, fn _, acc ->
      case :queue.out(acc) do
        {{:value, _}, new_buffer} -> new_buffer
        {:empty, buffer} -> buffer
      end
    end)
  end

  defp process_buffered_audio(input_buffer, output_buffer, _state) do
    # For now, just move chunks from input to output
    # In the future, this could apply audio processing effects
    case :queue.out(input_buffer) do
      {{:value, chunk}, _} ->
        new_output_buffer = :queue.in(chunk, output_buffer)
        {new_output_buffer, 1}

      {:empty, _} ->
        {output_buffer, 0}
    end
  end

  defp extract_chunks(buffer, 0, acc), do: {Enum.reverse(acc), buffer}

  defp extract_chunks(buffer, count, acc) do
    case :queue.out(buffer) do
      {{:value, chunk}, new_buffer} ->
        extract_chunks(new_buffer, count - 1, [chunk | acc])

      {:empty, buffer} ->
        {Enum.reverse(acc), buffer}
    end
  end

  defp perform_format_conversion(data, source_format, target_format) do
    # This is a simplified conversion - in production, you'd use a proper
    # audio processing library like :portaudio or :sox
    cond do
      source_format == target_format ->
        data

      source_format.format == :float32 and target_format.format == :pcm16 ->
        convert_float32_to_pcm16(data)

      source_format.format == :pcm24 and target_format.format == :pcm16 ->
        convert_pcm24_to_pcm16(data)

      true ->
        # Fallback: assume data is already in correct format
        Logger.warning("Unsupported format conversion, using data as-is")
        data
    end
  end

  defp convert_float32_to_pcm16(float_data) do
    # Convert 32-bit float samples to 16-bit PCM
    for <<sample::float-32-little <- float_data>>, into: <<>> do
      # Clamp to [-1.0, 1.0] and convert to 16-bit integer
      clamped = max(-1.0, min(1.0, sample))
      pcm_value = round(clamped * 32767)
      <<pcm_value::signed-16-little>>
    end
  end

  defp convert_pcm24_to_pcm16(pcm24_data) do
    # Convert 24-bit PCM to 16-bit PCM by taking the upper 16 bits
    for <<sample::signed-24-little <- pcm24_data>>, into: <<>> do
      # Right shift by 8 bits to get 16-bit value
      pcm16_value = Bitwise.bsr(sample, 8)
      <<pcm16_value::signed-16-little>>
    end
  end

  defp pcm16_format(state) do
    %{
      sample_rate: state.sample_rate,
      channels: state.channels,
      bit_depth: 16,
      format: :pcm16
    }
  end

  defp update_processing_metrics(metrics, processing_time, processed_count, overflow_count) do
    new_total_time = metrics.total_processing_time_us + processing_time
    new_processed = metrics.chunks_processed + processed_count
    new_average = if new_processed > 0, do: new_total_time / new_processed, else: 0.0

    %{metrics |
      chunks_processed: new_processed,
      total_processing_time_us: new_total_time,
      average_processing_time_us: new_average,
      buffer_overflows: metrics.buffer_overflows + overflow_count,
      last_activity: DateTime.utc_now()
    }
  end

  defp update_error_metrics(state) do
    new_metrics = update_in(state.metrics, [:conversion_errors], &(&1 + 1))
    %{state | metrics: new_metrics}
  end

  defp trigger_callback(state, event, data) do
    case Map.get(state.callbacks, event) do
      nil -> :ok
      callback when is_function(callback, 2) ->
        try do
          callback.(event, data)
        rescue
          e -> Logger.error("Error in audio processor callback: #{inspect(e)}")
        end
      _ -> Logger.warning("Invalid callback for event: #{event}")
    end
  end
end
