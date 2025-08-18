defmodule LivekitexAgent.ToolRegistry do
  @moduledoc """
  Global registry for function tools.
  """

  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def register(tool_definition) do
    GenServer.call(__MODULE__, {:register, tool_definition})
  end

  def get(tool_name) do
    GenServer.call(__MODULE__, {:get, tool_name})
  end

  def get_all do
    GenServer.call(__MODULE__, :get_all)
  end

  def unregister(tool_name) do
    GenServer.call(__MODULE__, {:unregister, tool_name})
  end

  # GenServer callbacks

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:register, tool_definition}, _from, state) do
    updated_state = Map.put(state, tool_definition.name, tool_definition)
    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call({:get, tool_name}, _from, state) do
    tool = Map.get(state, tool_name)
    {:reply, tool, state}
  end

  @impl true
  def handle_call(:get_all, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:unregister, tool_name}, _from, state) do
    updated_state = Map.delete(state, tool_name)
    {:reply, :ok, updated_state}
  end
end
