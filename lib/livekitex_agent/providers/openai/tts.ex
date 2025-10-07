defmodule LivekitexAgent.Providers.OpenAI.TTS do
  @moduledoc """
  OpenAI Text-to-Speech provider for LivekitexAgent.

  Handles speech synthesis using OpenAI's TTS API for converting text
  to high-quality audio with multiple voice options and formats.

  Features:
  - Multiple voice models (alloy, echo, fable, onyx, nova, shimmer)
  - HD and standard quality models (tts-1, tts-1-hd)
  - Multiple output formats (mp3, opus, aac, flac, pcm)
  - Streaming and batch synthesis
  - Speed control (0.25x to 4.0x)
  - Real-time audio chunk delivery
  """

  use GenServer
  require Logger

  @default_model "tts-1"
  @default_voice "alloy"
  @default_format "pcm"
  @default_speed 1.0
  @api_base_url "https://api.openai.com/v1"
  @available_voices ~w(alloy echo fable onyx nova shimmer)
  @available_formats ~w(mp3 opus aac flac pcm)

  defstruct [
    :api_key,
    :model,
    :voice,
    :format,
    :speed,
    :parent,
    :http_client,
    :processing_task,
    :request_timeout,
    :streaming,
    :sample_rate
  ]

  @type t :: %__MODULE__{
          api_key: String.t(),
          model: String.t(),
          voice: String.t(),
          format: String.t(),
          speed: float(),
          parent: pid(),
          http_client: atom(),
          processing_task: Task.t() | nil,
          request_timeout: integer(),
          streaming: boolean(),
          sample_rate: integer()
        }

  # Client API

  @doc """
  Starts the OpenAI TTS provider.

  ## Options
  - `:api_key` - OpenAI API key (required)
  - `:model` - TTS model ("tts-1" or "tts-1-hd", default: "tts-1")
  - `:voice` - Voice to use (#{Enum.join(@available_voices, ", ")}, default: "alloy")
  - `:format` - Output format (#{Enum.join(@available_formats, ", ")}, default: "pcm")
  - `:speed` - Speech speed 0.25-4.0 (default: 1.0)
  - `:parent` - Parent process for audio chunks
  - `:streaming` - Enable streaming chunks (default: false)
  - `:sample_rate` - Sample rate for PCM format (default: 24000)
  - `:request_timeout` - HTTP request timeout in ms (default: 30000)

  ## Example
      {:ok, tts} = LivekitexAgent.Providers.OpenAI.TTS.start_link(
        api_key: "sk-...",
        voice: "nova",
        format: "pcm",
        parent: self()
      )
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Synthesizes text to speech.
  """
  def synthesize(tts_pid, text) do
    GenServer.cast(tts_pid, {:synthesize, text})
  end

  @doc """
  Stops current synthesis.
  """
  def stop(tts_pid) do
    GenServer.cast(tts_pid, :stop)
  end

  @doc """
  Updates the voice setting.
  """
  def set_voice(tts_pid, voice) when voice in @available_voices do
    GenServer.call(tts_pid, {:set_voice, voice})
  end

  @doc """
  Updates the speech speed.
  """
  def set_speed(tts_pid, speed) when speed >= 0.25 and speed <= 4.0 do
    GenServer.call(tts_pid, {:set_speed, speed})
  end

  @doc """
  Updates the output format.
  """
  def set_format(tts_pid, format) when format in @available_formats do
    GenServer.call(tts_pid, {:set_format, format})
  end

  @doc """
  Gets the current configuration and state.
  """
  def get_state(tts_pid) do
    GenServer.call(tts_pid, :get_state)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    voice = Keyword.get(opts, :voice, @default_voice)
    format = Keyword.get(opts, :format, @default_format)
    speed = Keyword.get(opts, :speed, @default_speed)

    # Validate options
    unless voice in @available_voices do
      raise ArgumentError, "Invalid voice: #{voice}. Must be one of: #{Enum.join(@available_voices, ", ")}"
    end

    unless format in @available_formats do
      raise ArgumentError, "Invalid format: #{format}. Must be one of: #{Enum.join(@available_formats, ", ")}"
    end

    unless speed >= 0.25 and speed <= 4.0 do
      raise ArgumentError, "Invalid speed: #{speed}. Must be between 0.25 and 4.0"
    end

    state = %__MODULE__{
      api_key: api_key,
      model: Keyword.get(opts, :model, @default_model),
      voice: voice,
      format: format,
      speed: speed,
      parent: Keyword.get(opts, :parent),
      http_client: HTTPoison,
      processing_task: nil,
      request_timeout: Keyword.get(opts, :request_timeout, 30_000),
      streaming: Keyword.get(opts, :streaming, false),
      sample_rate: Keyword.get(opts, :sample_rate, 24000)
    }

    Logger.info("OpenAI TTS provider started with voice: #{state.voice}, format: #{state.format}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:synthesize, text}, state) do
    Logger.debug("Synthesizing text: #{String.slice(text, 0, 100)}#{if String.length(text) > 100, do: "...", else: ""}")

    # Cancel any existing task
    state = maybe_cancel_task(state)

    case perform_synthesis(state, text) do
      {:ok, task} ->
        {:noreply, %{state | processing_task: task}}

      {:error, reason} ->
        Logger.error("Failed to start synthesis: #{inspect(reason)}")
        if state.parent, do: send(state.parent, {:tts_error, reason})
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:stop, state) do
    Logger.debug("Stopping TTS synthesis")

    state = maybe_cancel_task(state)
    if state.parent, do: send(state.parent, {:tts_stopped, :cancelled})

    {:noreply, state}
  end

  @impl true
  def handle_call({:set_voice, voice}, _from, state) do
    {:reply, :ok, %{state | voice: voice}}
  end

  @impl true
  def handle_call({:set_speed, speed}, _from, state) do
    {:reply, :ok, %{state | speed: speed}}
  end

  @impl true
  def handle_call({:set_format, format}, _from, state) do
    {:reply, :ok, %{state | format: format}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    state_info = %{
      model: state.model,
      voice: state.voice,
      format: state.format,
      speed: state.speed,
      streaming: state.streaming,
      sample_rate: state.sample_rate,
      processing: state.processing_task != nil
    }
    {:reply, state_info, state}
  end

  @impl true
  def handle_info({task_ref, result}, state) when is_reference(task_ref) do
    # Task completion
    case result do
      {:ok, audio_data} ->
        Logger.info("TTS synthesis completed: #{byte_size(audio_data)} bytes")

        if state.streaming do
          # Send audio in chunks for streaming
          send_audio_chunks(state.parent, audio_data)
        else
          # Send complete audio
          if state.parent, do: send(state.parent, {:tts_complete, audio_data})
        end

      {:error, error} ->
        Logger.error("TTS synthesis failed: #{inspect(error)}")
        if state.parent, do: send(state.parent, {:tts_error, error})
    end

    # Clean up task
    if state.processing_task && state.processing_task.ref == task_ref do
      {:noreply, %{state | processing_task: nil}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    # Task monitor cleanup
    Logger.debug("TTS task terminated: #{inspect(reason)}")
    {:noreply, %{state | processing_task: nil}}
  end

  # Private Functions

  defp maybe_cancel_task(state) do
    if state.processing_task do
      Task.shutdown(state.processing_task, :brutal_kill)
      %{state | processing_task: nil}
    else
      state
    end
  end

  defp perform_synthesis(state, text) do
    if String.trim(text) == "" do
      {:error, :empty_text}
    else
      task = Task.async(fn ->
        make_tts_request(state, text)
      end)
      {:ok, task}
    end
  end

  defp make_tts_request(state, text) do
    url = "#{@api_base_url}/audio/speech"

    headers = [
      {"Authorization", "Bearer #{state.api_key}"},
      {"Content-Type", "application/json"},
      {"User-Agent", "LivekitexAgent/1.0"}
    ]

    # Build request body
    body = %{
      model: state.model,
      input: text,
      voice: state.voice,
      response_format: state.format,
      speed: state.speed
    }

    case Jason.encode(body) do
      {:ok, json_body} ->
        case state.http_client.post(url, json_body, headers, timeout: state.request_timeout) do
          {:ok, %HTTPoison.Response{status_code: 200, body: audio_data}} ->
            {:ok, audio_data}

          {:ok, %HTTPoison.Response{status_code: status_code, body: error_body}} ->
            Logger.error("OpenAI TTS API error #{status_code}: #{error_body}")
            {:error, {:api_error, status_code, error_body}}

          {:error, error} ->
            Logger.error("HTTP request error: #{inspect(error)}")
            {:error, {:http_error, error}}
        end

      {:error, encode_error} ->
        Logger.error("JSON encoding error: #{inspect(encode_error)}")
        {:error, {:encoding_error, encode_error}}
    end
  end

  defp send_audio_chunks(parent, audio_data) when is_pid(parent) do
    # Send audio in manageable chunks (e.g., 4KB chunks)
    chunk_size = 4096

    audio_data
    |> Stream.unfold(fn
      <<chunk::binary-size(chunk_size), rest::binary>> -> {chunk, rest}
      <<rest::binary>> when byte_size(rest) > 0 -> {rest, <<>>}
      <<>> -> nil
    end)
    |> Enum.each(fn chunk ->
      send(parent, {:tts_audio, chunk})
      # Small delay to prevent overwhelming the receiver
      Process.sleep(10)
    end)

    # Signal completion
    send(parent, {:tts_complete, byte_size(audio_data)})
  end

  defp send_audio_chunks(_parent, _audio_data), do: :ok
end
