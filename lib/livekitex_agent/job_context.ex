defmodule LivekitexAgent.JobContext do
  @moduledoc """
  Provides context and resources for a specific agent job execution.

  JobContext manages:
  - Room management and LiveKit room access
  - Process information about the running job
  - Connection and shutdown event handlers
  - Participant handling and entry points
  - Async task management within the job
  - Contextual logging with job-specific fields
  """

  use GenServer
  require Logger

  defstruct [
    :job_id,
    :room,
    :process_info,
    :callbacks,
    :participants,
    :tasks,
    :metadata,
    :logging_context,
    :created_at,
    :status,
    :error_count,
    :max_errors
  ]

  @type job_status :: :created | :running | :completed | :failed | :terminated

  @type t :: %__MODULE__{
          job_id: String.t(),
          room: map() | nil,
          process_info: map(),
          callbacks: map(),
          participants: map(),
          tasks: map(),
          metadata: map(),
          logging_context: map(),
          created_at: DateTime.t(),
          status: job_status(),
          error_count: non_neg_integer(),
          max_errors: pos_integer()
        }

  @doc """
  Creates a new job context.

  ## Options
  - `:job_id` - Unique identifier for the job
  - `:room` - LiveKit room configuration
  - `:callbacks` - Map of event callbacks
  - `:metadata` - Additional metadata for the job
  - `:max_errors` - Maximum allowed errors before job termination

  ## Example
      iex> LivekitexAgent.JobContext.new(
      ...>   job_id: "job_123",
      ...>   room: %{name: "meeting_room", token: "..."},
      ...>   callbacks: %{
      ...>     on_participant_connected: &handle_participant/1,
      ...>     on_shutdown: &cleanup/0
      ...>   }
      ...> )
  """
  def new(opts \\ []) do
    %__MODULE__{
      job_id: Keyword.get(opts, :job_id, generate_job_id()),
      room: Keyword.get(opts, :room),
      process_info: get_process_info(),
      callbacks: Keyword.get(opts, :callbacks, %{}),
      participants: %{},
      tasks: %{},
      metadata: Keyword.get(opts, :metadata, %{}),
      logging_context: build_logging_context(opts),
      created_at: DateTime.utc_now(),
      status: :created,
      error_count: 0,
      max_errors: Keyword.get(opts, :max_errors, 10)
    }
  end

  @doc """
  Starts the job context as a supervised GenServer.
  """
  def start_link(opts \\ []) do
    job_context = new(opts)
    GenServer.start_link(__MODULE__, job_context, name: {:global, job_context.job_id})
  end

  @doc """
  Gets the current job status.
  """
  def get_status(job_context_or_pid) do
    call_or_access(job_context_or_pid, :get_status)
  end

  @doc """
  Gets job information including process details and runtime stats.
  """
  def get_info(job_context_or_pid) do
    call_or_access(job_context_or_pid, :get_info)
  end

  @doc """
  Adds a participant to the job context.
  """
  def add_participant(job_context_or_pid, participant_id, participant_info) do
    call_or_access(job_context_or_pid, {:add_participant, participant_id, participant_info})
  end

  @doc """
  Removes a participant from the job context.
  """
  def remove_participant(job_context_or_pid, participant_id) do
    call_or_access(job_context_or_pid, {:remove_participant, participant_id})
  end

  @doc """
  Gets all participants in the job.
  """
  def get_participants(job_context_or_pid) do
    call_or_access(job_context_or_pid, :get_participants)
  end

  @doc """
  Starts a new task within the job context.
  """
  def start_task(job_context_or_pid, task_name, task_fun) do
    call_or_access(job_context_or_pid, {:start_task, task_name, task_fun})
  end

  @doc """
  Stops a specific task.
  """
  def stop_task(job_context_or_pid, task_name) do
    call_or_access(job_context_or_pid, {:stop_task, task_name})
  end

  @doc """
  Gets all running tasks.
  """
  def get_tasks(job_context_or_pid) do
    call_or_access(job_context_or_pid, :get_tasks)
  end

  @doc """
  Registers a callback for job events.
  """
  def register_callback(job_context_or_pid, event, callback_fun) do
    call_or_access(job_context_or_pid, {:register_callback, event, callback_fun})
  end

  @doc """
  Logs a message with job context.
  """
  def log_info(job_context_or_pid, message, metadata \\ %{}) do
    context = get_logging_context(job_context_or_pid)
    Logger.info(message, Map.merge(context, metadata))
  end

  @doc """
  Logs an error with job context.
  """
  def log_error(job_context_or_pid, message, metadata \\ %{}) do
    context = get_logging_context(job_context_or_pid)
    Logger.error(message, Map.merge(context, metadata))

    # Increment error count if this is a GenServer
    if is_pid(job_context_or_pid) do
      GenServer.cast(job_context_or_pid, :increment_error_count)
    end
  end

  @doc """
  Gracefully shuts down the job.
  """
  def shutdown(job_context_or_pid, reason \\ :normal) do
    call_or_access(job_context_or_pid, {:shutdown, reason})
  end

  # GenServer callbacks

  @impl true
  def init(job_context) do
    Logger.info("Job context started", job_context.logging_context)

    # Set up process monitoring
    Process.flag(:trap_exit, true)

    job_context = %{job_context | status: :running}
    emit_callback(job_context, :on_job_started, job_context)

    {:ok, job_context}
  end

  @impl true
  def handle_call(:get_status, _from, job_context) do
    {:reply, job_context.status, job_context}
  end

  @impl true
  def handle_call(:get_info, _from, job_context) do
    info = %{
      job_id: job_context.job_id,
      status: job_context.status,
      created_at: job_context.created_at,
      uptime: DateTime.diff(DateTime.utc_now(), job_context.created_at, :second),
      participants_count: map_size(job_context.participants),
      tasks_count: map_size(job_context.tasks),
      error_count: job_context.error_count,
      process_info: job_context.process_info,
      metadata: job_context.metadata
    }

    {:reply, info, job_context}
  end

  @impl true
  def handle_call({:add_participant, participant_id, participant_info}, _from, job_context) do
    participants = Map.put(job_context.participants, participant_id, participant_info)
    job_context = %{job_context | participants: participants}

    log_info(job_context, "Participant joined: #{participant_id}")
    emit_callback(job_context, :on_participant_connected, {participant_id, participant_info})

    {:reply, :ok, job_context}
  end

  @impl true
  def handle_call({:remove_participant, participant_id}, _from, job_context) do
    {removed, participants} = Map.pop(job_context.participants, participant_id)
    job_context = %{job_context | participants: participants}

    if removed do
      log_info(job_context, "Participant left: #{participant_id}")
      emit_callback(job_context, :on_participant_disconnected, {participant_id, removed})
    end

    {:reply, if(removed, do: :ok, else: :not_found), job_context}
  end

  @impl true
  def handle_call(:get_participants, _from, job_context) do
    {:reply, job_context.participants, job_context}
  end

  @impl true
  def handle_call({:start_task, task_name, task_fun}, _from, job_context) do
    case Map.get(job_context.tasks, task_name) do
      nil ->
        task_pid = Task.start(task_fun)

        case task_pid do
          {:ok, pid} ->
            tasks =
              Map.put(job_context.tasks, task_name, %{
                pid: pid,
                started_at: DateTime.utc_now(),
                status: :running
              })

            job_context = %{job_context | tasks: tasks}
            log_info(job_context, "Task started: #{task_name}")
            {:reply, {:ok, pid}, job_context}

          {:error, reason} ->
            log_error(job_context, "Failed to start task #{task_name}: #{inspect(reason)}")
            {:reply, {:error, reason}, job_context}
        end

      _existing ->
        {:reply, {:error, :already_exists}, job_context}
    end
  end

  @impl true
  def handle_call({:stop_task, task_name}, _from, job_context) do
    case Map.get(job_context.tasks, task_name) do
      %{pid: pid} = task_info ->
        Task.shutdown(pid, :brutal_kill)
        tasks = Map.put(job_context.tasks, task_name, %{task_info | status: :stopped})
        job_context = %{job_context | tasks: tasks}

        log_info(job_context, "Task stopped: #{task_name}")
        {:reply, :ok, job_context}

      nil ->
        {:reply, {:error, :not_found}, job_context}
    end
  end

  @impl true
  def handle_call(:get_tasks, _from, job_context) do
    {:reply, job_context.tasks, job_context}
  end

  @impl true
  def handle_call({:register_callback, event, callback_fun}, _from, job_context) do
    callbacks = Map.put(job_context.callbacks, event, callback_fun)
    job_context = %{job_context | callbacks: callbacks}
    {:reply, :ok, job_context}
  end

  @impl true
  def handle_call({:shutdown, reason}, _from, job_context) do
    log_info(job_context, "Job shutting down: #{inspect(reason)}")

    # Stop all tasks
    Enum.each(job_context.tasks, fn {_name, %{pid: pid}} ->
      Task.shutdown(pid)
    end)

    job_context = %{job_context | status: :completed}
    emit_callback(job_context, :on_shutdown, reason)

    {:stop, :normal, :ok, job_context}
  end

  @impl true
  def handle_cast(:increment_error_count, job_context) do
    error_count = job_context.error_count + 1
    job_context = %{job_context | error_count: error_count}

    if error_count >= job_context.max_errors do
      log_error(job_context, "Maximum error count reached (#{error_count}), terminating job")
      job_context = %{job_context | status: :failed}
      emit_callback(job_context, :on_max_errors_reached, error_count)
      {:stop, :too_many_errors, job_context}
    else
      {:noreply, job_context}
    end
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, job_context) do
    # Handle task termination
    task_name = find_task_by_pid(job_context.tasks, pid)

    if task_name do
      log_info(job_context, "Task #{task_name} terminated: #{inspect(reason)}")

      tasks =
        Map.put(job_context.tasks, task_name, %{
          job_context.tasks[task_name]
          | status: :terminated,
            terminated_at: DateTime.utc_now(),
            termination_reason: reason
        })

      job_context = %{job_context | tasks: tasks}
      emit_callback(job_context, :on_task_terminated, {task_name, reason})
    end

    {:noreply, job_context}
  end

  @impl true
  def terminate(reason, job_context) do
    log_info(job_context, "Job context terminating: #{inspect(reason)}")

    # Clean up all tasks
    Enum.each(job_context.tasks, fn {_name, %{pid: pid}} ->
      Task.shutdown(pid)
    end)

    emit_callback(job_context, :on_job_terminated, reason)
    :ok
  end

  # Private functions

  defp call_or_access(%__MODULE__{} = job_context, message) do
    # Direct struct access for synchronous operations
    case message do
      :get_status -> job_context.status
      :get_info -> build_info(job_context)
      :get_participants -> job_context.participants
      :get_tasks -> job_context.tasks
      _ -> {:error, :not_supported_on_struct}
    end
  end

  defp call_or_access(pid, message) when is_pid(pid) do
    GenServer.call(pid, message)
  end

  defp generate_job_id do
    timestamp = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "job_#{timestamp}_#{random}"
  end

  defp get_process_info do
    %{
      pid: self(),
      node: node(),
      started_at: DateTime.utc_now(),
      memory_usage: :erlang.process_info(self(), :memory),
      message_queue_len: :erlang.process_info(self(), :message_queue_len)
    }
  end

  defp build_logging_context(opts) do
    job_id = Keyword.get(opts, :job_id, generate_job_id())

    %{
      job_id: job_id,
      node: node(),
      pid: inspect(self())
    }
  end

  defp get_logging_context(%__MODULE__{} = job_context) do
    job_context.logging_context
  end

  defp get_logging_context(pid) when is_pid(pid) do
    case GenServer.call(pid, :get_info) do
      %{job_id: job_id} -> %{job_id: job_id, pid: inspect(pid)}
      _ -> %{pid: inspect(pid)}
    end
  end

  defp build_info(job_context) do
    %{
      job_id: job_context.job_id,
      status: job_context.status,
      created_at: job_context.created_at,
      uptime: DateTime.diff(DateTime.utc_now(), job_context.created_at, :second),
      participants_count: map_size(job_context.participants),
      tasks_count: map_size(job_context.tasks),
      error_count: job_context.error_count,
      process_info: job_context.process_info,
      metadata: job_context.metadata
    }
  end

  defp emit_callback(job_context, event, data) do
    case Map.get(job_context.callbacks, event) do
      nil ->
        :ok

      callback_fun when is_function(callback_fun) ->
        try do
          callback_fun.(data)
        rescue
          error ->
            log_error(job_context, "Error in callback #{event}: #{inspect(error)}")
        end
    end
  end

  defp find_task_by_pid(tasks, pid) do
    Enum.find_value(tasks, fn {name, %{pid: task_pid}} ->
      if task_pid == pid, do: name, else: nil
    end)
  end
end
