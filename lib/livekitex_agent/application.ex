defmodule LivekitexAgent.Application do
  @moduledoc """
  The main application module for LivekitexAgent.

  This module starts the application supervision tree and initializes
  core components like the tool registry.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting LivekitexAgent application")

    children = [
      # Tool registry for global tool management
      {LivekitexAgent.ToolRegistry, []}
    ]

    opts = [strategy: :one_for_one, name: LivekitexAgent.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("LivekitexAgent application started successfully")
        register_default_tools()
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start LivekitexAgent application: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def stop(_state) do
    Logger.info("LivekitexAgent application stopped")
    :ok
  end

  defp register_default_tools do
    # Register example tools
    tools = LivekitexAgent.ExampleTools.get_tools()

    Enum.each(tools, fn {_name, tool_def} ->
      LivekitexAgent.ToolRegistry.register(tool_def)
    end)

    Logger.info("Default tools registered: #{map_size(tools)} tools")
  end
end
