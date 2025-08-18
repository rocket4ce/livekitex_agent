defmodule LivekitexAgent.WorkerSupervisor do
  @moduledoc """
  Supervisor for agent workers and their components.
  """

  use Supervisor
  require Logger

  def start_link(worker_options) do
    Supervisor.start_link(__MODULE__, worker_options, name: __MODULE__)
  end

  @impl true
  def init(worker_options) do
    Logger.info("Starting worker supervisor with options: #{inspect(worker_options.agent_name)}")

    children = [
      # Tool registry
      {LivekitexAgent.ToolRegistry, []},

      # Worker manager
      {LivekitexAgent.WorkerManager, worker_options},

      # Health check server (optional)
      {LivekitexAgent.HealthServer, worker_options}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
