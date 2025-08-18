defmodule LivekitexAgent.HealthServer do
  @moduledoc """
  HTTP server for health checks and metrics.
  """

  use GenServer
  require Logger

  def start_link(worker_options) do
    GenServer.start_link(__MODULE__, worker_options, name: __MODULE__)
  end

  @impl true
  def init(worker_options) do
    port = Map.get(worker_options, :port, 8080)

    # In a real implementation, this would start an HTTP server
    # For now, just log that it would be started
    Logger.info("Health server would start on port #{port}")

    {:ok, %{worker_options: worker_options, port: port}}
  end

  def handle_health_check do
    # Return health status
    %{
      status: "healthy",
      timestamp: DateTime.utc_now(),
      version: get_version()
    }
  end

  def handle_metrics do
    # Return metrics
    %{
      active_jobs: get_active_jobs_count(),
      memory_usage: get_memory_usage(),
      uptime: get_uptime()
    }
  end

  defp get_version do
    case :application.get_key(:livekitex_agent, :vsn) do
      {:ok, version} -> to_string(version)
      :undefined -> "unknown"
    end
  end

  defp get_active_jobs_count do
    case LivekitexAgent.WorkerManager.get_status() do
      %{active_jobs_count: count} -> count
      _ -> 0
    end
  end

  defp get_memory_usage do
    :erlang.memory(:total)
  end

  defp get_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_ms
  end
end
