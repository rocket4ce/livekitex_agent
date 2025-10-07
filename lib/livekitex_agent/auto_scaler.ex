defmodule LivekitexAgent.AutoScaler do
  @moduledoc """
  Automatic worker pool scaling based on system metrics and load patterns.
  """

  use GenServer
  require Logger

  defstruct [
    :config,
    :scaling_history,
    :last_scale_time
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @impl true
  def init(opts) do
    config = %{
      enabled: Keyword.get(opts, :enabled, false),
      min_workers: Keyword.get(opts, :min_workers, 1),
      max_workers: Keyword.get(opts, :max_workers, 10)
    }

    state = %__MODULE__{
      config: config,
      scaling_history: [],
      last_scale_time: nil
    }

    Logger.info("AutoScaler started")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      enabled: state.config.enabled,
      min_workers: state.config.min_workers,
      max_workers: state.config.max_workers,
      scaling_history: Enum.take(state.scaling_history, 10)
    }

    {:reply, status, state}
  end
end
