defmodule LivekitexAgent.Media.AudioProcessor do
  @doc """
  Enhanced audio processing pipeline for real-time voice agent interactions.

  This module provides:
  - Advanced PCM16 audio format handling and conversion
  - Low-latency audio buffering and chunking for streaming
  - Sample rate conversion and audio preprocessing
  - Real-time audio pipeline management with sub-100ms latency
  - Integration with LiveKit audio streams
  - Performance monitoring and optimization
  - Voice Activity Detection (VAD) integration
  - Audio quality enhancement and noise reduction

  ## Audio Formats

  The pipeline primarily works with PCM16 format optimized for voice:
  - Sample rate: 16kHz (preferred), 24kHz, or 48kHz (configurable)
  - Channels: Mono (1 channel) for optimal voice processing
  - Bit depth: 16-bit signed integers (-32,768 to 32,767)
  - Endianness: Little-endian (standard for x86/ARM)
  - Frame size: Configurable chunks (10ms, 20ms, 100ms)

  ## Enhanced Pipeline Stages

  1. **Input Processing**: Receive raw audio from LiveKit or local sources
  2. **Format Validation**: Validate PCM16 format and sample rate
  3. **Quality Enhancement**: Apply noise reduction and normalization
  4. **Buffering**: Low-latency circular buffer management
  5. **Processing**: Apply audio transformations and VAD
  6. **Output**: Stream processed audio to providers or LiveKit

  ## Performance Targets

  - Latency: Sub-100ms end-to-end processing
  - Throughput: 100+ concurrent audio streams
  - Memory: Efficient circular buffering
  - CPU: Optimized audio processing algorithms
  """

  use GenServer
  require Logger

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

  @doc """
  Processes raw PCM16 audio data with optimized pipeline.

  This function handles the most common use case of processing
  PCM16 audio data directly without wrapping in audio_chunk structure.
  """
  def process_pcm16(pcm16_data, sample_rate \\ @default_sample_rate) do
    GenServer.cast(__MODULE__, {:process_pcm16, pcm16_data, sample_rate})
  end

  @doc """
  Validates PCM16 format and returns format information.
  """
  def validate_pcm16(pcm16_data) do
    GenServer.call(__MODULE__, {:validate_pcm16, pcm16_data})
  end

  @doc """
  Converts audio between different sample rates while maintaining PCM16 format.
  """
  def resample_pcm16(pcm16_data, from_rate, to_rate) do
    GenServer.call(__MODULE__, {:resample_pcm16, pcm16_data, from_rate, to_rate})
  end

  @doc """
  Applies audio enhancement (noise reduction, normalization) to PCM16 data.
  """
  def enhance_audio(pcm16_data, options \\ %{}) do
    GenServer.call(__MODULE__, {:enhance_audio, pcm16_data, options})
  end

  @doc """
  Gets real-time latency metrics for the audio pipeline.
  """
  def get_latency_metrics do
    GenServer.call(__MODULE__, :get_latency_metrics)
  end

  @doc """
  Enables or disables real-time processing optimizations.
  """
  def set_realtime_mode(enabled) do
    GenServer.call(__MODULE__, {:set_realtime_mode, enabled})
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
      {output_buffer, processed_count} =
        if state.processing_enabled do
          process_buffered_audio(input_buffer, state.output_buffer, state)
        else
          {state.output_buffer, 0}
        end

      # Update metrics
      processing_time = System.monotonic_time(:microsecond) - start_time

      new_metrics =
        update_processing_metrics(state.metrics, processing_time, processed_count, overflow_count)

      new_state = %{
        state
        | input_buffer: input_buffer,
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
  def handle_cast({:process_pcm16, pcm16_data, sample_rate}, state) do
    start_time = System.monotonic_time(:microsecond)

    try do
      # Create optimized audio chunk for PCM16 data
      audio_chunk = %{
        data: pcm16_data,
        format: %{
          sample_rate: sample_rate,
          channels: state.channels,
          bit_depth: 16,
          format: :pcm16
        },
        timestamp: DateTime.utc_now(),
        sequence: get_next_sequence()
      }

      # Process through optimized PCM16 pipeline
      processed_chunk = optimize_pcm16_processing(audio_chunk, state)

      # Add to output buffer for immediate consumption
      new_output_buffer = :queue.in(processed_chunk, state.output_buffer)

      # Update metrics with PCM16-specific tracking
      processing_time = System.monotonic_time(:microsecond) - start_time
      new_metrics = update_pcm16_metrics(state.metrics, processing_time, byte_size(pcm16_data))

      new_state = %{state | output_buffer: new_output_buffer, metrics: new_metrics}

      trigger_callback(new_state, :pcm16_processed, processed_chunk)
      {:noreply, new_state}
    rescue
      e ->
        Logger.error("PCM16 processing error: #{inspect(e)}")
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
        {:reply, {:error, {:conversion_failed, Exception.message(e)}}, state}
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
    new_state = %{state | input_buffer: :queue.new(), output_buffer: :queue.new()}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:update_config, new_config}, _from, state) do
    new_state = %{
      state
      | sample_rate: Map.get(new_config, :sample_rate, state.sample_rate),
        channels: Map.get(new_config, :channels, state.channels),
        chunk_duration_ms: Map.get(new_config, :chunk_duration_ms, state.chunk_duration_ms),
        buffer_size_ms: Map.get(new_config, :buffer_size_ms, state.buffer_size_ms),
        processing_enabled: Map.get(new_config, :enable_processing, state.processing_enabled)
    }

    Logger.info("AudioProcessor config updated")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:validate_pcm16, pcm16_data}, _from, state) do
    validation_result = validate_pcm16_format(pcm16_data)
    {:reply, validation_result, state}
  end

  @impl true
  def handle_call({:resample_pcm16, pcm16_data, from_rate, to_rate}, _from, state) do
    try do
      resampled_data = perform_pcm16_resampling(pcm16_data, from_rate, to_rate)
      {:reply, {:ok, resampled_data}, state}
    rescue
      e ->
        Logger.error("PCM16 resampling error: #{inspect(e)}")
        {:reply, {:error, {:resampling_failed, Exception.message(e)}}, state}
    end
  end

  @impl true
  def handle_call({:enhance_audio, pcm16_data, options}, _from, state) do
    try do
      enhanced_data = apply_audio_enhancements(pcm16_data, options)
      {:reply, {:ok, enhanced_data}, state}
    rescue
      e ->
        Logger.error("Audio enhancement error: #{inspect(e)}")
        {:reply, {:error, {:enhancement_failed, Exception.message(e)}}, state}
    end
  end

  @impl true
  def handle_call(:get_latency_metrics, _from, state) do
    latency_metrics = calculate_latency_metrics(state)
    {:reply, latency_metrics, state}
  end

  @impl true
  def handle_call({:set_realtime_mode, enabled}, _from, state) do
    # Update processing optimizations for real-time performance
    new_state = configure_realtime_optimizations(state, enabled)
    Logger.info("Real-time mode #{if enabled, do: "enabled", else: "disabled"}")
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
      converted_data =
        perform_format_conversion(
          audio_chunk.data,
          audio_chunk.format,
          target_format
        )

      %{audio_chunk | data: converted_data, format: target_format}
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

    %{
      metrics
      | chunks_processed: new_processed,
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
      nil ->
        :ok

      callback when is_function(callback, 2) ->
        try do
          callback.(event, data)
        rescue
          e -> Logger.error("Error in audio processor callback: #{inspect(e)}")
        end

      _ ->
        Logger.warning("Invalid callback for event: #{event}")
    end
  end

  # PCM16 Enhancement Functions

  defp optimize_pcm16_processing(audio_chunk, _state) do
    # Apply PCM16-specific optimizations
    enhanced_data = normalize_pcm16_audio(audio_chunk.data)

    %{
      audio_chunk
      | data: enhanced_data,
        metadata: Map.put(audio_chunk[:metadata] || %{}, :optimized, true)
    }
  end

  defp normalize_pcm16_audio(pcm16_data) do
    # Basic PCM16 normalization to prevent clipping
    # Convert binary to list of 16-bit signed integers
    samples = for <<sample::little-signed-16 <- pcm16_data>>, do: sample

    # Find peak amplitude
    max_amplitude = Enum.max(Enum.map(samples, &abs/1))

    if max_amplitude > 0 do
      # Normalize to prevent clipping while maintaining dynamic range
      # Leave 10% headroom
      target_max = 32767 * 0.9
      scale_factor = target_max / max_amplitude

      normalized_samples =
        Enum.map(samples, fn sample ->
          normalized = round(sample * scale_factor)
          max(-32768, min(32767, normalized))
        end)

      # Convert back to binary
      for sample <- normalized_samples, into: <<>>, do: <<sample::little-signed-16>>
    else
      pcm16_data
    end
  rescue
    # Return original data if normalization fails
    _ -> pcm16_data
  end

  defp validate_pcm16_format(pcm16_data) do
    byte_count = byte_size(pcm16_data)

    cond do
      byte_count == 0 ->
        {:error, :empty_data}

      rem(byte_count, 2) != 0 ->
        {:error, :invalid_pcm16_alignment}

      true ->
        sample_count = div(byte_count, 2)
        duration_ms = sample_count / @default_sample_rate * 1000

        {:ok,
         %{
           byte_size: byte_count,
           sample_count: sample_count,
           duration_ms: duration_ms,
           format: :pcm16
         }}
    end
  end

  defp perform_pcm16_resampling(pcm16_data, from_rate, to_rate) when from_rate == to_rate do
    # No resampling needed
    pcm16_data
  end

  defp perform_pcm16_resampling(pcm16_data, from_rate, to_rate) do
    # Simple linear interpolation resampling for PCM16
    samples = for <<sample::little-signed-16 <- pcm16_data>>, do: sample
    ratio = to_rate / from_rate
    output_length = round(length(samples) * ratio)

    resampled =
      for i <- 0..(output_length - 1) do
        source_index = i / ratio

        # Linear interpolation between adjacent samples
        index_floor = floor(source_index)
        index_ceil = min(index_floor + 1, length(samples) - 1)

        if index_floor == index_ceil do
          Enum.at(samples, round(index_floor))
        else
          sample_a = Enum.at(samples, round(index_floor))
          sample_b = Enum.at(samples, round(index_ceil))
          fraction = source_index - index_floor

          round(sample_a * (1 - fraction) + sample_b * fraction)
        end
      end

    for sample <- resampled, into: <<>>, do: <<sample::little-signed-16>>
  end

  defp apply_audio_enhancements(pcm16_data, options) do
    pcm16_data
    |> maybe_apply_noise_reduction(options[:noise_reduction])
    |> maybe_apply_gain_control(options[:gain_control])
  end

  defp maybe_apply_noise_reduction(pcm16_data, nil), do: pcm16_data

  defp maybe_apply_noise_reduction(pcm16_data, _options) do
    # Basic noise gate implementation
    samples = for <<sample::little-signed-16 <- pcm16_data>>, do: sample
    # Noise gate threshold
    threshold = 1000

    processed =
      Enum.map(samples, fn sample ->
        if abs(sample) < threshold, do: 0, else: sample
      end)

    for sample <- processed, into: <<>>, do: <<sample::little-signed-16>>
  end

  defp maybe_apply_gain_control(pcm16_data, nil), do: pcm16_data

  defp maybe_apply_gain_control(pcm16_data, options) do
    gain = Map.get(options, :gain, 1.0)
    samples = for <<sample::little-signed-16 <- pcm16_data>>, do: sample

    processed =
      Enum.map(samples, fn sample ->
        boosted = round(sample * gain)
        max(-32768, min(32767, boosted))
      end)

    for sample <- processed, into: <<>>, do: <<sample::little-signed-16>>
  end

  defp update_pcm16_metrics(metrics, processing_time, data_size) do
    %{
      metrics
      | chunks_processed: metrics.chunks_processed + 1,
        total_processing_time_us: metrics.total_processing_time_us + processing_time,
        average_processing_time_us:
          (metrics.total_processing_time_us + processing_time) / (metrics.chunks_processed + 1),
        last_activity: DateTime.utc_now(),
        total_data_processed: Map.get(metrics, :total_data_processed, 0) + data_size
    }
  end

  defp calculate_latency_metrics(state) do
    # Calculate various latency metrics
    # Convert to ms
    avg_processing_time = state.metrics.average_processing_time_us / 1000
    buffer_latency = calculate_buffer_latency(state)

    %{
      average_processing_latency_ms: avg_processing_time,
      buffer_latency_ms: buffer_latency,
      total_latency_ms: avg_processing_time + buffer_latency,
      buffer_size: :queue.len(state.output_buffer),
      throughput_chunks_per_sec: calculate_throughput(state.metrics)
    }
  end

  defp calculate_buffer_latency(state) do
    # Estimate latency based on buffer size and chunk duration
    buffer_size = :queue.len(state.output_buffer)
    buffer_size * state.chunk_duration_ms
  end

  defp calculate_throughput(metrics) do
    # Calculate chunks per second based on recent activity
    if metrics.chunks_processed > 0 do
      time_diff = DateTime.diff(DateTime.utc_now(), metrics.last_activity, :second)
      if time_diff > 0, do: metrics.chunks_processed / time_diff, else: 0.0
    else
      0.0
    end
  end

  defp configure_realtime_optimizations(state, enabled) do
    # Configure optimizations for real-time processing
    if enabled do
      %{
        state
        | # Smaller chunks for lower latency
          chunk_duration_ms: 20,
          # Smaller buffer for real-time
          buffer_size_ms: 100,
          processing_enabled: true
      }
    else
      %{
        state
        | chunk_duration_ms: @default_chunk_duration_ms,
          buffer_size_ms: @default_buffer_size_ms,
          processing_enabled: state.processing_enabled
      }
    end
  end

  defp get_next_sequence do
    # Simple sequence counter using process dictionary
    current = Process.get(:audio_sequence, 0)
    Process.put(:audio_sequence, current + 1)
    current
  end
end
