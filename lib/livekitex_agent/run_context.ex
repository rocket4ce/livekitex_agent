defmodule LivekitexAgent.RunContext do
  @moduledoc """
  Context object passed during function tool execution.

  RunContext provides:
  - Access to the current AgentSession
  - Speech handle for controlling current speech generation
  - Function call information about the current function being executed
  - Access to session-specific user data
  - Utilities for tool execution
  """

  require Logger

  defstruct [
    :session,
    :speech_handle,
    :function_call,
    :user_data,
    :execution_id,
    :started_at,
    :metadata
  ]

  @type t :: %__MODULE__{
          session: pid() | nil,
          speech_handle: map() | nil,
          function_call: map(),
          user_data: map(),
          execution_id: String.t(),
          started_at: DateTime.t(),
          metadata: map()
        }

  @doc """
  Creates a new RunContext for tool execution.

  ## Parameters
  - `opts` - Keyword list of options
    - `:session` - The current AgentSession pid
    - `:speech_handle` - Handle for controlling speech generation
    - `:function_call` - Information about the function being called
    - `:user_data` - Session-specific user data
    - `:metadata` - Additional metadata for the execution

  ## Example
      iex> context = LivekitexAgent.RunContext.new(
      ...>   session: session_pid,
      ...>   function_call: %{name: "get_weather", arguments: %{location: "NYC"}},
      ...>   user_data: %{user_id: "123", preferences: %{}}
      ...> )
  """
  def new(opts \\ []) do
    %__MODULE__{
      session: Keyword.get(opts, :session),
      speech_handle: Keyword.get(opts, :speech_handle),
      function_call: Keyword.get(opts, :function_call, %{}),
      user_data: Keyword.get(opts, :user_data, %{}),
      execution_id: generate_execution_id(),
      started_at: DateTime.utc_now(),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Gets the function name being executed.
  """
  def get_function_name(%__MODULE__{function_call: %{name: name}}) do
    name
  end

  def get_function_name(_), do: nil

  @doc """
  Gets the function arguments.
  """
  def get_function_arguments(%__MODULE__{function_call: %{arguments: args}}) do
    args
  end

  def get_function_arguments(_), do: %{}

  @doc """
  Gets a specific function argument by key.
  """
  def get_argument(%__MODULE__{} = context, key) do
    get_function_arguments(context) |> Map.get(key)
  end

  @doc """
  Gets user data for the current session.
  """
  def get_user_data(%__MODULE__{user_data: user_data}) do
    user_data
  end

  @doc """
  Gets a specific piece of user data by key.
  """
  def get_user_data(%__MODULE__{user_data: user_data}, key) do
    Map.get(user_data, key)
  end

  @doc """
  Sets user data for the session.
  """
  def put_user_data(%__MODULE__{} = context, key, value) do
    updated_user_data = Map.put(context.user_data, key, value)

    # Also update the session if available
    if context.session do
      send(context.session, {:update_user_data, key, value})
    end

    %{context | user_data: updated_user_data}
  end

  @doc """
  Gets the current session pid.
  """
  def get_session(%__MODULE__{session: session}) do
    session
  end

  @doc """
  Gets session information if session is available.
  """
  def get_session_info(%__MODULE__{session: nil}) do
    {:error, :no_session}
  end

  def get_session_info(%__MODULE__{session: session}) do
    try do
      LivekitexAgent.AgentSession.get_state(session)
    rescue
      _ -> {:error, :session_unavailable}
    end
  end

  @doc """
  Interrupts the current speech generation.
  """
  def interrupt_speech(%__MODULE__{session: nil}) do
    {:error, :no_session}
  end

  def interrupt_speech(%__MODULE__{session: session}) do
    LivekitexAgent.AgentSession.interrupt(session)
  end

  @doc """
  Controls speech generation with the speech handle.
  """
  def control_speech(%__MODULE__{speech_handle: nil}, _action) do
    {:error, :no_speech_handle}
  end

  def control_speech(%__MODULE__{speech_handle: handle}, action) do
    case action do
      :pause ->
        send_speech_command(handle, :pause)

      :resume ->
        send_speech_command(handle, :resume)

      :stop ->
        send_speech_command(handle, :stop)

      {:set_volume, volume} when is_number(volume) and volume >= 0 and volume <= 1 ->
        send_speech_command(handle, {:set_volume, volume})

      _ ->
        {:error, :invalid_action}
    end
  end

  @doc """
  Logs a message with execution context.
  """
  def log_info(%__MODULE__{} = context, message, metadata \\ %{}) do
    log_context = build_log_context(context)
    Logger.info(message, Map.merge(log_context, metadata))
  end

  @doc """
  Logs an error with execution context.
  """
  def log_error(%__MODULE__{} = context, message, metadata \\ %{}) do
    log_context = build_log_context(context)
    Logger.error(message, Map.merge(log_context, metadata))
  end

  @doc """
  Logs a warning with execution context.
  """
  def log_warning(%__MODULE__{} = context, message, metadata \\ %{}) do
    log_context = build_log_context(context)
    Logger.warning(message, Map.merge(log_context, metadata))
  end

  @doc """
  Gets execution metrics and timing information.
  """
  def get_execution_metrics(%__MODULE__{} = context) do
    now = DateTime.utc_now()
    duration = DateTime.diff(now, context.started_at, :millisecond)

    %{
      execution_id: context.execution_id,
      function_name: get_function_name(context),
      started_at: context.started_at,
      current_time: now,
      duration_ms: duration,
      has_session: context.session != nil,
      has_speech_handle: context.speech_handle != nil
    }
  end

  @doc """
  Creates a child context for nested tool execution.
  """
  def create_child_context(%__MODULE__{} = parent_context, function_call) do
    %__MODULE__{
      session: parent_context.session,
      speech_handle: parent_context.speech_handle,
      function_call: function_call,
      user_data: parent_context.user_data,
      execution_id: generate_execution_id(),
      started_at: DateTime.utc_now(),
      metadata:
        Map.put(parent_context.metadata, :parent_execution_id, parent_context.execution_id)
    }
  end

  @doc """
  Validates that the context has required components.
  """
  def validate(%__MODULE__{} = context, requirements \\ []) do
    Enum.reduce_while(requirements, {:ok, context}, fn requirement, acc ->
      case requirement do
        :session ->
          if context.session, do: {:cont, acc}, else: {:halt, {:error, :session_required}}

        :speech_handle ->
          if context.speech_handle,
            do: {:cont, acc},
            else: {:halt, {:error, :speech_handle_required}}

        :function_call ->
          if context.function_call != %{},
            do: {:cont, acc},
            else: {:halt, {:error, :function_call_required}}

        {:argument, arg_name} ->
          if Map.has_key?(get_function_arguments(context), arg_name) do
            {:cont, acc}
          else
            {:halt, {:error, {:argument_required, arg_name}}}
          end

        _ ->
          {:halt, {:error, {:unknown_requirement, requirement}}}
      end
    end)
  end

  @doc """
  Executes a function with proper error handling and logging.
  """
  def execute_with_context(%__MODULE__{} = context, fun) when is_function(fun, 1) do
    log_info(context, "Starting function execution: #{get_function_name(context)}")

    start_time = System.monotonic_time(:millisecond)

    try do
      result = fun.(context)

      duration = System.monotonic_time(:millisecond) - start_time
      log_info(context, "Function execution completed", %{duration_ms: duration})

      {:ok, result}
    rescue
      error ->
        duration = System.monotonic_time(:millisecond) - start_time

        log_error(context, "Function execution failed: #{inspect(error)}", %{
          duration_ms: duration,
          error: inspect(error),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        })

        {:error, error}
    end
  end

  # Private functions

  defp generate_execution_id do
    timestamp = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "exec_#{timestamp}_#{random}"
  end

  defp send_speech_command(%{pid: pid}, command) when is_pid(pid) do
    send(pid, {:speech_control, command})
    :ok
  end

  defp send_speech_command(%{module: module, ref: ref}, command) do
    apply(module, :control_speech, [ref, command])
  end

  defp send_speech_command(handle, command) when is_function(handle) do
    handle.(command)
  end

  defp send_speech_command(_, _) do
    {:error, :invalid_speech_handle}
  end

  defp build_log_context(%__MODULE__{} = context) do
    %{
      execution_id: context.execution_id,
      function_name: get_function_name(context) || "unknown",
      session: if(context.session, do: inspect(context.session), else: "none"),
      duration_ms: DateTime.diff(DateTime.utc_now(), context.started_at, :millisecond)
    }
  end
end
