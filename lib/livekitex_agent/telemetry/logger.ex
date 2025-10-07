defmodule LivekitexAgent.Telemetry.Logger do
  @moduledoc """
  Structured logging utilities for LiveKit agent operations.

  This module provides:
  - Structured logging with consistent field names
  - Performance monitoring and request tracing
  - Agent-specific log contexts and metadata
  - Integration with telemetry events
  - Configurable log levels and formatting
  - Request correlation and session tracking

  ## Log Structure

  All structured logs include:
  - `timestamp` - ISO8601 formatted timestamp
  - `level` - Log level (debug, info, warn, error)
  - `message` - Human-readable message
  - `context` - Structured context data
  - `correlation_id` - Request/session correlation ID
  - `component` - Component generating the log
  - `duration_ms` - Operation duration (when applicable)

  ## Usage

      # Basic structured logging
      Logger.info("Agent started", agent_id: "abc123", state: :active)

      # Performance monitoring
      Logger.log_duration("Tool execution", start_time,
        tool: :get_weather, params: %{city: "SF"})

      # Error logging with context
      Logger.log_error(exception, "Failed to process audio",
        session_id: "xyz789", chunk_size: 1024)
  """

  require Logger

  @default_component "livekitex_agent"

  defstruct [
    :component,
    :correlation_id,
    :session_id,
    :agent_id,
    :metadata
  ]

  @type log_context :: %__MODULE__{
          component: String.t(),
          correlation_id: String.t() | nil,
          session_id: String.t() | nil,
          agent_id: String.t() | nil,
          metadata: map()
        }

  @type log_level :: :debug | :info | :warn | :error

  ## Context Management

  @doc """
  Creates a new log context for structured logging.
  """
  def new_context(opts \\ []) do
    %__MODULE__{
      component: Keyword.get(opts, :component, @default_component),
      correlation_id: Keyword.get(opts, :correlation_id, generate_correlation_id()),
      session_id: Keyword.get(opts, :session_id),
      agent_id: Keyword.get(opts, :agent_id),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Updates an existing log context with new values.
  """
  def update_context(context, opts) do
    %{
      context
      | component: Keyword.get(opts, :component, context.component),
        correlation_id: Keyword.get(opts, :correlation_id, context.correlation_id),
        session_id: Keyword.get(opts, :session_id, context.session_id),
        agent_id: Keyword.get(opts, :agent_id, context.agent_id),
        metadata: Map.merge(context.metadata, Keyword.get(opts, :metadata, %{}))
    }
  end

  @doc """
  Gets the current process log context.
  """
  def get_context do
    Process.get(:log_context, new_context())
  end

  @doc """
  Sets the log context for the current process.
  """
  def set_context(context) do
    Process.put(:log_context, context)
  end

  @doc """
  Executes a function with a specific log context.
  """
  def with_context(context, fun) do
    old_context = get_context()
    set_context(context)

    try do
      fun.()
    after
      set_context(old_context)
    end
  end

  ## Structured Logging Functions

  @doc """
  Logs a debug message with structured context.
  """
  def debug(message, fields \\ []) do
    log(:debug, message, fields)
  end

  @doc """
  Logs an info message with structured context.
  """
  def info(message, fields \\ []) do
    log(:info, message, fields)
  end

  @doc """
  Logs a warning message with structured context.
  """
  def warn(message, fields \\ []) do
    log(:warn, message, fields)
  end

  @doc """
  Logs an error message with structured context.
  """
  def error(message, fields \\ []) do
    log(:error, message, fields)
  end

  @doc """
  Logs a message at the specified level with structured context.
  """
  def log(level, message, fields \\ []) do
    context = get_context()
    structured_log = build_structured_log(level, message, fields, context)

    case level do
      :debug -> Logger.debug(fn -> format_log(structured_log) end)
      :info -> Logger.info(fn -> format_log(structured_log) end)
      :warn -> Logger.warning(fn -> format_log(structured_log) end)
      :error -> Logger.error(fn -> format_log(structured_log) end)
    end
  end

  ## Performance Monitoring

  @doc """
  Logs the duration of an operation with context.

  ## Examples

      start_time = System.monotonic_time(:millisecond)
      # ... perform operation ...
      Logger.log_duration("Database query", start_time,
        query: "SELECT * FROM users", rows: 42)
  """
  def log_duration(operation, start_time, fields \\ []) do
    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time

    fields_with_duration =
      [
        operation: operation,
        duration_ms: duration_ms,
        start_time: start_time,
        end_time: end_time
      ] ++ fields

    level = if duration_ms > 5000, do: :warn, else: :info
    log(level, "Operation completed: #{operation}", fields_with_duration)
  end

  @doc """
  Times a function execution and logs the duration.
  """
  def time_function(operation, fun, fields \\ []) do
    start_time = System.monotonic_time(:millisecond)

    try do
      result = fun.()
      log_duration(operation, start_time, [{:result, :success} | fields])
      result
    rescue
      e ->
        log_duration(operation, start_time, [{:result, :error}, {:error, Exception.message(e)} | fields])
        reraise e, __STACKTRACE__
    end
  end

  ## Error Logging

  @doc """
  Logs an exception with full context and stack trace.
  """
  def log_error(exception, message, fields \\ [], stacktrace \\ nil) do
    error_fields = [
      error_type: exception.__struct__,
      error_message: Exception.message(exception)
    ]

    error_fields =
      if stacktrace do
        [{:stacktrace, Exception.format_stacktrace(stacktrace)} | error_fields]
      else
        error_fields
      end

    error(message, error_fields ++ fields)
  end

  @doc """
  Logs an error with additional context when an operation fails.
  """
  def log_operation_error(operation, error, fields \\ []) do
    error_fields =
      [
        operation: operation,
        error: inspect(error),
        failed_at: DateTime.utc_now()
      ] ++ fields

    error("Operation failed: #{operation}", error_fields)
  end

  ## Agent-Specific Logging

  @doc """
  Logs agent lifecycle events (started, stopped, configured, etc.).
  """
  def log_agent_event(event, agent_id, fields \\ []) do
    context = get_context() |> update_context(agent_id: agent_id)

    with_context(context, fn ->
      info("Agent #{event}", [{:agent_event, event}, {:agent_id, agent_id} | fields])
    end)
  end

  @doc """
  Logs session-related events with session context.
  """
  def log_session_event(event, session_id, fields \\ []) do
    context = get_context() |> update_context(session_id: session_id)

    with_context(context, fn ->
      info("Session #{event}", [{:session_event, event}, {:session_id, session_id} | fields])
    end)
  end

  @doc """
  Logs tool execution events with tool context.
  """
  def log_tool_execution(tool_name, result, duration_ms, fields \\ []) do
    level =
      case result do
        {:ok, _} -> :info
        {:error, _} -> :error
      end

    tool_fields =
      [
        tool: tool_name,
        tool_result: result,
        duration_ms: duration_ms,
        executed_at: DateTime.utc_now()
      ] ++ fields

    log(level, "Tool executed: #{tool_name}", tool_fields)
  end

  @doc """
  Logs provider interactions (LLM, STT, TTS, VAD).
  """
  def log_provider_interaction(
        provider_type,
        provider,
        operation,
        result,
        duration_ms,
        fields \\ []
      ) do
    level =
      case result do
        {:ok, _} -> :info
        {:error, _} -> :warn
      end

    provider_fields =
      [
        provider_type: provider_type,
        provider: provider,
        operation: operation,
        result: result,
        duration_ms: duration_ms
      ] ++ fields

    log(level, "Provider #{operation}: #{provider}", provider_fields)
  end

  ## Audio Processing Logging

  @doc """
  Logs audio processing events with audio-specific context.
  """
  def log_audio_event(event, fields \\ []) do
    audio_fields =
      [
        audio_event: event,
        timestamp: DateTime.utc_now()
      ] ++ fields

    info("Audio #{event}", audio_fields)
  end

  @doc """
  Logs audio processing performance metrics.
  """
  def log_audio_metrics(metrics, fields \\ []) do
    metrics_fields =
      [
        audio_metrics: metrics,
        measured_at: DateTime.utc_now()
      ] ++ fields

    debug("Audio processing metrics", metrics_fields)
  end

  ## Private Functions

  defp build_structured_log(level, message, fields, context) do
    base_log = %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      level: level,
      message: message,
      component: context.component
    }

    # Add correlation ID if present
    log_with_correlation =
      if context.correlation_id do
        Map.put(base_log, :correlation_id, context.correlation_id)
      else
        base_log
      end

    # Add session ID if present
    log_with_session =
      if context.session_id do
        Map.put(log_with_correlation, :session_id, context.session_id)
      else
        log_with_correlation
      end

    # Add agent ID if present
    log_with_agent =
      if context.agent_id do
        Map.put(log_with_session, :agent_id, context.agent_id)
      else
        log_with_session
      end

    # Merge context metadata and provided fields
    all_context = Map.merge(context.metadata, Enum.into(fields, %{}))

    if map_size(all_context) > 0 do
      Map.put(log_with_agent, :context, all_context)
    else
      log_with_agent
    end
  end

  defp format_log(structured_log) do
    case Application.get_env(:livekitex_agent, :log_format, :json) do
      :json -> Jason.encode!(structured_log)
      :pretty -> format_pretty_log(structured_log)
      _ -> format_simple_log(structured_log)
    end
  end

  defp format_pretty_log(log) do
    timestamp = Map.get(log, :timestamp, "")
    level = Map.get(log, :level, :info) |> Atom.to_string() |> String.upcase()
    message = Map.get(log, :message, "")
    component = Map.get(log, :component, "")

    context_str =
      case Map.get(log, :context) do
        nil -> ""
        context when map_size(context) == 0 -> ""
        context -> " #{inspect(context)}"
      end

    correlation_str =
      case Map.get(log, :correlation_id) do
        nil -> ""
        id -> " [#{id}]"
      end

    "#{timestamp} [#{level}] #{component}#{correlation_str}: #{message}#{context_str}"
  end

  defp format_simple_log(log) do
    level = Map.get(log, :level, :info) |> Atom.to_string() |> String.upcase()
    message = Map.get(log, :message, "")

    "[#{level}] #{message}"
  end

  defp generate_correlation_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
