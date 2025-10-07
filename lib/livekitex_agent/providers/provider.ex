defmodule LivekitexAgent.Providers.Provider do
  @moduledoc """
  Base behaviour for AI service providers (LLM, STT, TTS, VAD).

  This behaviour defines the common interface that all providers must implement,
  including configuration validation, service initialization, health checking,
  and graceful error handling with circuit breaker patterns.

  ## Provider Types

  - `:llm` - Large Language Model providers (OpenAI GPT, Claude, etc.)
  - `:stt` - Speech-to-Text providers (OpenAI Whisper, Google STT, etc.)
  - `:tts` - Text-to-Speech providers (OpenAI TTS, ElevenLabs, etc.)
  - `:vad` - Voice Activity Detection providers (WebRTC VAD, etc.)

  ## Implementation Requirements

  Each provider must implement:
  - Configuration validation
  - Service initialization and connection
  - Request processing with appropriate input/output formats
  - Health checking and monitoring
  - Graceful error handling and recovery
  - Resource cleanup on shutdown
  """

  @type provider_type :: :llm | :stt | :tts | :vad

  @type config ::
          %{
            provider: atom(),
            type: provider_type()
          }
          | map()

  @type init_result :: {:ok, state :: any()} | {:error, reason :: any()}

  @type process_result :: {:ok, result :: any()} | {:error, reason :: any()}

  @type health_status :: :healthy | :degraded | :unhealthy

  @type health_check_result :: %{
          status: health_status(),
          latency_ms: non_neg_integer() | nil,
          last_check: DateTime.t(),
          error: String.t() | nil
        }

  @doc """
  Validates provider configuration.

  Should check that all required configuration parameters are present
  and valid for the specific provider implementation.
  """
  @callback validate_config(config()) :: :ok | {:error, reason :: any()}

  @doc """
  Initializes the provider with the given configuration.

  This is called once when the provider is started and should establish
  any necessary connections or prepare resources.
  """
  @callback init(config()) :: init_result()

  @doc """
  Processes a request through the provider service.

  The input and output formats depend on the provider type:
  - LLM: input is conversation context, output is generated response
  - STT: input is audio data, output is transcribed text
  - TTS: input is text, output is audio data
  - VAD: input is audio chunk, output is voice activity probability
  """
  @callback process(request :: any(), state :: any()) :: process_result()

  @doc """
  Performs a health check on the provider service.

  Should verify that the service is reachable and functioning properly.
  This is used for monitoring and circuit breaker logic.
  """
  @callback health_check(state :: any()) :: health_check_result()

  @doc """
  Handles provider configuration updates.

  Called when configuration changes need to be applied without
  restarting the provider entirely.
  """
  @callback handle_config_change(new_config :: config(), state :: any()) :: init_result()

  @doc """
  Cleans up provider resources on shutdown.

  Should close connections, release resources, and perform any
  necessary cleanup operations.
  """
  @callback terminate(reason :: any(), state :: any()) :: :ok

  # Optional callbacks with default implementations

  @doc """
  Returns provider-specific metrics.

  Default implementation returns empty metrics.
  """
  @callback get_metrics(state :: any()) :: map()

  @doc """
  Handles provider-specific events or notifications.

  Default implementation ignores all events.
  """
  @callback handle_event(event :: any(), state :: any()) :: {:ok, state :: any()}

  # Provide default implementations for optional callbacks
  @optional_callbacks [get_metrics: 1, handle_event: 2]

  defmacro __using__(opts) do
    provider_type = Keyword.get(opts, :type, :unknown)

    quote do
      @behaviour LivekitexAgent.Providers.Provider

      @provider_type unquote(provider_type)

      def get_metrics(_state), do: %{}
      def handle_event(_event, state), do: {:ok, state}

      defoverridable get_metrics: 1, handle_event: 2

      @doc """
      Returns the provider type for this implementation.
      """
      def provider_type, do: @provider_type
    end
  end

  @doc """
  Creates a new provider instance with the given module and configuration.

  This is a helper function that validates configuration and initializes
  the provider in a standardized way.
  """
  def new(provider_module, config) do
    with :ok <- provider_module.validate_config(config),
         {:ok, state} <- provider_module.init(config) do
      {:ok, {provider_module, state}}
    end
  end

  @doc """
  Processes a request through a provider instance.

  Handles the provider call with error handling and monitoring.
  """
  def process({provider_module, state}, request) do
    try do
      provider_module.process(request, state)
    rescue
      e ->
        {:error, {:provider_error, e.message}}
    catch
      :exit, reason ->
        {:error, {:provider_exit, reason}}
    end
  end

  @doc """
  Performs a health check on a provider instance.
  """
  def health_check({provider_module, state}) do
    try do
      provider_module.health_check(state)
    rescue
      e ->
        %{
          status: :unhealthy,
          latency_ms: nil,
          last_check: DateTime.utc_now(),
          error: e.message
        }
    catch
      :exit, reason ->
        %{
          status: :unhealthy,
          latency_ms: nil,
          last_check: DateTime.utc_now(),
          error: "Provider exit: #{inspect(reason)}"
        }
    end
  end

  @doc """
  Updates provider configuration.
  """
  def update_config({provider_module, _state}, new_config) do
    with :ok <- provider_module.validate_config(new_config),
         {:ok, new_state} <- provider_module.handle_config_change(new_config, nil) do
      {:ok, {provider_module, new_state}}
    end
  end

  @doc """
  Gets metrics from a provider instance.
  """
  def get_metrics({provider_module, state}) do
    try do
      provider_module.get_metrics(state)
    rescue
      _ -> %{}
    end
  end

  @doc """
  Terminates a provider instance.
  """
  def terminate({provider_module, state}, reason) do
    try do
      provider_module.terminate(reason, state)
    rescue
      _ -> :ok
    end
  end
end
