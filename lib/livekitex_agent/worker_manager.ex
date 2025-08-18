defmodule LivekitexAgent.WorkerManager do
  @moduledoc """
  Manages worker processes and job distribution.
  """

  use GenServer
  require Logger

  defstruct [
    :worker_options,
    :active_jobs,
    :job_supervisor
  ]

  def start_link(worker_options) do
    GenServer.start_link(__MODULE__, worker_options, name: __MODULE__)
  end

  def assign_job(job_request) do
    GenServer.call(__MODULE__, {:assign_job, job_request})
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @impl true
  def init(worker_options) do
    # Start job supervisor
    {:ok, job_supervisor_pid} = Task.Supervisor.start_link()

    state = %__MODULE__{
      worker_options: worker_options,
      active_jobs: %{},
      job_supervisor: job_supervisor_pid
    }

    Logger.info("Worker manager started for agent: #{worker_options.agent_name}")

    {:ok, state}
  end

  @impl true
  def handle_call({:assign_job, job_request}, _from, state) do
    case LivekitexAgent.WorkerOptions.should_handle_job?(state.worker_options, job_request) do
      {:accept, :ok} ->
        job_context =
          LivekitexAgent.JobContext.new(
            job_id: Map.get(job_request, :job_id, generate_job_id()),
            room: Map.get(job_request, :room),
            metadata: Map.get(job_request, :metadata, %{})
          )

        # Start job in supervised task
        task =
          Task.Supervisor.async(state.job_supervisor, fn ->
            state.worker_options.entry_point.(job_context)
          end)

        active_jobs =
          Map.put(state.active_jobs, job_context.job_id, %{
            context: job_context,
            task: task,
            started_at: DateTime.utc_now()
          })

        state = %{state | active_jobs: active_jobs}

        Logger.info("Job assigned: #{job_context.job_id}")
        {:reply, {:ok, job_context.job_id}, state}

      {:reject, reason} ->
        Logger.info("Job rejected: #{reason}")
        {:reply, {:rejected, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      agent_name: state.worker_options.agent_name,
      active_jobs_count: map_size(state.active_jobs),
      max_concurrent_jobs: state.worker_options.max_concurrent_jobs,
      current_load: LivekitexAgent.WorkerOptions.current_load(state.worker_options),
      load_threshold: state.worker_options.load_threshold
    }

    {:reply, status, state}
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Job completed
    case find_job_by_task_ref(state.active_jobs, ref) do
      {job_id, _job_info} ->
        Logger.info("Job completed: #{job_id}, result: #{inspect(result)}")

        active_jobs = Map.delete(state.active_jobs, job_id)
        state = %{state | active_jobs: active_jobs}

        # Clean up the task reference
        Process.demonitor(ref, [:flush])

        {:noreply, state}

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Job crashed
    case find_job_by_task_ref(state.active_jobs, ref) do
      {job_id, _job_info} ->
        Logger.error("Job crashed: #{job_id}, reason: #{inspect(reason)}")

        active_jobs = Map.delete(state.active_jobs, job_id)
        state = %{state | active_jobs: active_jobs}

        {:noreply, state}

      nil ->
        {:noreply, state}
    end
  end

  defp generate_job_id do
    timestamp = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "job_#{timestamp}_#{random}"
  end

  defp find_job_by_task_ref(active_jobs, ref) do
    Enum.find(active_jobs, fn {_job_id, job_info} ->
      job_info.task.ref == ref
    end)
  end
end
