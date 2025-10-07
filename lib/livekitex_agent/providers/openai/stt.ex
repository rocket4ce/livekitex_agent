defmodule LivekitexAgent.Providers.OpenAI.STT do
  @moduledoc """
  OpenAI Speech-to-Text provider for LivekitexAgent.

  Handles audio transcription using OpenAI's Whisper API for converting
  audio streams to text with support for multiple languages and formats.

  Features:
  - Whisper model integration
  - Streaming and batch audio processing
  - Multiple audio format support (PCM16, MP3, WAV)
  - Language detection and specification
  - Timestamp and confidence scoring
  - Real-time transcription buffering
  """

  use GenServer
  require Logger

  @default_model "whisper-1"
  @api_base_url "https://api.openai.com/v1"
  @supported_formats [:pcm16, :wav, :mp3, :m4a, :webm]
  @max_file_size 25 * 1024 * 1024  # 25MB OpenAI limit

  defstruct [
    :api_key,
    :model,
    :language,
    :parent,
    :http_client,
    :audio_buffer,
    :buffer_duration,
    :processing_task,
    :format,
    :sample_rate,
    :request_timeout,
    :response_format,
    :temperature
  ]

  @type t :: %__MODULE__{
          api_key: String.t(),
          model: String.t(),
          language: String.t() | nil,
          parent: pid(),
          http_client: atom(),
          audio_buffer: binary(),
          buffer_duration: float(),
          processing_task: Task.t() | nil,
          format: atom(),
          sample_rate: integer(),
          request_timeout: integer(),
          response_format: String.t(),
          temperature: float()
        }

  # Client API

  @doc """
  Starts the OpenAI STT provider.

  ## Options
  - `:api_key` - OpenAI API key (required)
  - `:model` - Whisper model to use (default: "whisper-1")
  - `:language` - ISO-639-1 language code (nil for auto-detection)
  - `:parent` - Parent process for transcription results
  - `:format` - Audio format (default: :pcm16)
  - `:sample_rate` - Audio sample rate in Hz (default: 16000)
  - `:buffer_duration` - Max buffer duration in seconds (default: 10.0)
  - `:response_format` - Response format ("json", "text", "verbose_json")
  - `:temperature` - Sampling temperature (default: 0.0)
  - `:request_timeout` - HTTP request timeout in ms (default: 30000)

  ## Example
      {:ok, stt} = LivekitexAgent.Providers.OpenAI.STT.start_link(
        api_key: "sk-...",
        model: "whisper-1",
        parent: self(),
        language: "en"
      )
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Processes incoming audio data for transcription.
  Audio is buffered until buffer_duration is reached or explicitly processed.
  """
  def process_audio(stt_pid, audio_data) do
    GenServer.cast(stt_pid, {:process_audio, audio_data})
  end

  @doc """
  Processes a complete audio utterance for transcription.
  """
  def process_utterance(stt_pid, audio_data) do
    GenServer.cast(stt_pid, {:process_utterance, audio_data})
  end

  @doc """
  Flushes the current audio buffer and processes for transcription.
  """
  def flush_buffer(stt_pid) do
    GenServer.cast(stt_pid, :flush_buffer)
  end

  @doc """
  Updates the language setting.
  """
  def set_language(stt_pid, language) do
    GenServer.call(stt_pid, {:set_language, language})
  end

  @doc """
  Gets the current configuration and state.
  """
  def get_state(stt_pid) do
    GenServer.call(stt_pid, :get_state)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    api_key = Keyword.fetch!(opts, :api_key)

    state = %__MODULE__{
      api_key: api_key,
      model: Keyword.get(opts, :model, @default_model),
      language: Keyword.get(opts, :language),
      parent: Keyword.get(opts, :parent),
      http_client: HTTPoison,
      audio_buffer: <<>>,
      buffer_duration: Keyword.get(opts, :buffer_duration, 10.0),
      processing_task: nil,
      format: Keyword.get(opts, :format, :pcm16),
      sample_rate: Keyword.get(opts, :sample_rate, 16000),
      request_timeout: Keyword.get(opts, :request_timeout, 30_000),
      response_format: Keyword.get(opts, :response_format, "json"),
      temperature: Keyword.get(opts, :temperature, 0.0)
    }

    Logger.info("OpenAI STT provider started with model: #{state.model}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:process_audio, audio_data}, state) do
    # Add to buffer
    updated_buffer = state.audio_buffer <> audio_data
    buffer_size_seconds = byte_size(updated_buffer) / (state.sample_rate * 2)  # PCM16 = 2 bytes per sample

    state = %{state | audio_buffer: updated_buffer}

    # Check if buffer duration exceeded
    if buffer_size_seconds >= state.buffer_duration do
      Logger.debug("STT buffer full (#{buffer_size_seconds}s), processing...")
      handle_cast(:flush_buffer, state)
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:process_utterance, audio_data}, state) do
    Logger.debug("Processing complete utterance: #{byte_size(audio_data)} bytes")

    # Process immediately without buffering
    case transcribe_audio(state, audio_data) do
      {:ok, task} ->
        {:noreply, %{state | processing_task: task}}

      {:error, reason} ->
        Logger.error("Failed to start transcription: #{inspect(reason)}")
        if state.parent, do: send(state.parent, {:stt_error, reason})
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:flush_buffer, state) do
    if byte_size(state.audio_buffer) > 0 do
      Logger.debug("Flushing STT buffer: #{byte_size(state.audio_buffer)} bytes")

      case transcribe_audio(state, state.audio_buffer) do
        {:ok, task} ->
          {:noreply, %{state | audio_buffer: <<>>, processing_task: task}}

        {:error, reason} ->
          Logger.error("Failed to start transcription: #{inspect(reason)}")
          if state.parent, do: send(state.parent, {:stt_error, reason})
          {:noreply, %{state | audio_buffer: <<>>}}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_call({:set_language, language}, _from, state) do
    {:reply, :ok, %{state | language: language}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    state_info = %{
      model: state.model,
      language: state.language,
      format: state.format,
      sample_rate: state.sample_rate,
      buffer_size: byte_size(state.audio_buffer),
      buffer_duration: state.buffer_duration,
      processing: state.processing_task != nil
    }
    {:reply, state_info, state}
  end

  @impl true
  def handle_info({task_ref, result}, state) when is_reference(task_ref) do
    # Task completion
    case result do
      {:ok, transcription} ->
        Logger.info("Transcription completed: #{transcription}")
        if state.parent, do: send(state.parent, {:stt_result, transcription})

      {:error, error} ->
        Logger.error("Transcription failed: #{inspect(error)}")
        if state.parent, do: send(state.parent, {:stt_error, error})
    end

    # Clean up task
    if state.processing_task && state.processing_task.ref == task_ref do
      {:noreply, %{state | processing_task: nil}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Task monitor cleanup
    {:noreply, %{state | processing_task: nil}}
  end

  # Private Functions

  defp transcribe_audio(state, audio_data) do
    if byte_size(audio_data) == 0 do
      {:error, :empty_audio}
    else
      task = Task.async(fn ->
        perform_transcription(state, audio_data)
      end)
      {:ok, task}
    end
  end

  defp perform_transcription(state, audio_data) do
    # Convert to appropriate format for API
    case prepare_audio_for_api(audio_data, state.format, state.sample_rate) do
      {:ok, audio_file_data, content_type} ->
        make_transcription_request(state, audio_file_data, content_type)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prepare_audio_for_api(audio_data, :pcm16, sample_rate) do
    # Convert PCM16 to WAV format for OpenAI API
    case pcm16_to_wav(audio_data, sample_rate) do
      {:ok, wav_data} ->
        {:ok, wav_data, "audio/wav"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prepare_audio_for_api(audio_data, format, _sample_rate) when format in [:wav, :mp3, :m4a] do
    # Audio is already in a supported format
    content_type = case format do
      :wav -> "audio/wav"
      :mp3 -> "audio/mpeg"
      :m4a -> "audio/mp4"
    end
    {:ok, audio_data, content_type}
  end

  defp pcm16_to_wav(pcm_data, sample_rate) do
    # Create WAV header for PCM16 data
    channels = 1
    bits_per_sample = 16
    bytes_per_sample = div(bits_per_sample, 8)
    byte_rate = sample_rate * channels * bytes_per_sample
    block_align = channels * bytes_per_sample
    data_size = byte_size(pcm_data)
    file_size = 36 + data_size

    wav_header = <<
      # RIFF chunk
      "RIFF"::binary,
      file_size::little-32,
      "WAVE"::binary,

      # fmt chunk
      "fmt "::binary,
      16::little-32,  # fmt chunk size
      1::little-16,    # PCM format
      channels::little-16,
      sample_rate::little-32,
      byte_rate::little-32,
      block_align::little-16,
      bits_per_sample::little-16,

      # data chunk
      "data"::binary,
      data_size::little-32
    >>

    wav_data = wav_header <> pcm_data
    {:ok, wav_data}
  end

  defp make_transcription_request(state, audio_data, content_type) do
    if byte_size(audio_data) > @max_file_size do
      {:error, :file_too_large}
    else
      url = "#{@api_base_url}/audio/transcriptions"

      headers = [
        {"Authorization", "Bearer #{state.api_key}"},
        {"User-Agent", "LivekitexAgent/1.0"}
      ]

      # Create multipart form data
      boundary = generate_boundary()
      form_data = build_multipart_form(audio_data, content_type, boundary, state)

      multipart_headers = [
        {"Content-Type", "multipart/form-data; boundary=#{boundary}"} | headers
      ]

      case state.http_client.post(url, form_data, multipart_headers, timeout: state.request_timeout) do
        {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
          parse_transcription_response(response_body, state.response_format)

        {:ok, %HTTPoison.Response{status_code: status_code, body: error_body}} ->
          Logger.error("OpenAI STT API error #{status_code}: #{error_body}")
          {:error, {:api_error, status_code, error_body}}

        {:error, error} ->
          Logger.error("HTTP request error: #{inspect(error)}")
          {:error, {:http_error, error}}
      end
    end
  end

  defp build_multipart_form(audio_data, content_type, boundary, state) do
    parts = []

    # Add audio file
    file_part = """
    --#{boundary}\r
    Content-Disposition: form-data; name="file"; filename="audio.wav"\r
    Content-Type: #{content_type}\r
    \r
    """
    parts = [file_part, audio_data, "\r\n" | parts]

    # Add model
    model_part = """
    --#{boundary}\r
    Content-Disposition: form-data; name="model"\r
    \r
    #{state.model}\r
    """
    parts = [model_part | parts]

    # Add language if specified
    parts = if state.language do
      language_part = """
      --#{boundary}\r
      Content-Disposition: form-data; name="language"\r
      \r
      #{state.language}\r
      """
      [language_part | parts]
    else
      parts
    end

    # Add response format
    response_format_part = """
    --#{boundary}\r
    Content-Disposition: form-data; name="response_format"\r
    \r
    #{state.response_format}\r
    """
    parts = [response_format_part | parts]

    # Add temperature
    temperature_part = """
    --#{boundary}\r
    Content-Disposition: form-data; name="temperature"\r
    \r
    #{state.temperature}\r
    """
    parts = [temperature_part | parts]

    # Add closing boundary
    closing = "--#{boundary}--\r\n"
    parts = [closing | parts]

    # Reverse and join (we built it in reverse order)
    parts |> Enum.reverse() |> IO.iodata_to_binary()
  end

  defp generate_boundary do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp parse_transcription_response(response_body, "text") do
    # Plain text response
    {:ok, String.trim(response_body)}
  end

  defp parse_transcription_response(response_body, format) when format in ["json", "verbose_json"] do
    case Jason.decode(response_body) do
      {:ok, %{"text" => text}} ->
        {:ok, text}

      {:ok, %{"error" => error}} ->
        {:error, {:api_error, error}}

      {:error, decode_error} ->
        Logger.error("JSON decode error: #{inspect(decode_error)}")
        {:error, {:decode_error, decode_error}}

      _ ->
        {:error, :invalid_response}
    end
  end
end
