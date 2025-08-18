defmodule LivekitexAgent.Agent do
  @moduledoc """
  The main agent module that encapsulates the behavior and configuration of a voice agent.

  This module provides:
  - Instructions that guide the agent's behavior
  - Tools available to the agent for executing tasks
  - Chat context for maintaining conversation history
  - Component configuration (STT, TTS, LLM, VAD)
  - Behavioral settings (turn detection, interruption handling)
  """

  use GenServer

  defstruct [
    :instructions,
    :tools,
    :chat_context,
    :stt_config,
    :tts_config,
    :llm_config,
    :vad_config,
    :turn_detection_settings,
    :interruption_settings,
    :agent_id,
    :metadata
  ]

  @type t :: %__MODULE__{
          instructions: String.t(),
          tools: list(atom()),
          chat_context: map(),
          stt_config: map(),
          tts_config: map(),
          llm_config: map(),
          vad_config: map(),
          turn_detection_settings: map(),
          interruption_settings: map(),
          agent_id: String.t(),
          metadata: map()
        }

  @doc """
  Creates a new agent with the given configuration.

  ## Options
  - `:instructions` - Core instructions that guide the agent's behavior
  - `:tools` - List of function tools available to the agent
  - `:stt_config` - Speech-to-text configuration
  - `:tts_config` - Text-to-speech configuration
  - `:llm_config` - Language model configuration
  - `:vad_config` - Voice activity detection configuration

  ## Example
      iex> LivekitexAgent.Agent.new(
      ...>   instructions: "You are a helpful assistant",
      ...>   tools: [:get_weather, :search_web]
      ...> )
  """
  def new(opts \\ []) do
    %__MODULE__{
      instructions: Keyword.get(opts, :instructions, ""),
      tools: Keyword.get(opts, :tools, []),
      chat_context: Keyword.get(opts, :chat_context, %{}),
      stt_config: Keyword.get(opts, :stt_config, %{}),
      tts_config: Keyword.get(opts, :tts_config, %{}),
      llm_config: Keyword.get(opts, :llm_config, %{}),
      vad_config: Keyword.get(opts, :vad_config, %{}),
      turn_detection_settings: Keyword.get(opts, :turn_detection_settings, %{}),
      interruption_settings: Keyword.get(opts, :interruption_settings, %{}),
      agent_id: Keyword.get(opts, :agent_id, generate_id()),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Starts the agent as a GenServer.
  """
  def start_link(agent, opts \\ []) do
    GenServer.start_link(__MODULE__, agent, opts)
  end

  @doc """
  Updates the agent's instructions.
  """
  def update_instructions(agent, instructions) when is_struct(agent, __MODULE__) do
    %{agent | instructions: instructions}
  end

  def update_instructions(pid, instructions) when is_pid(pid) do
    GenServer.call(pid, {:update_instructions, instructions})
  end

  @doc """
  Adds a tool to the agent's available tools.
  """
  def add_tool(agent, tool) when is_struct(agent, __MODULE__) do
    %{agent | tools: [tool | agent.tools]}
  end

  def add_tool(pid, tool) when is_pid(pid) do
    GenServer.call(pid, {:add_tool, tool})
  end

  @doc """
  Gets the agent's current configuration.
  """
  def get_config(pid) when is_pid(pid) do
    GenServer.call(pid, :get_config)
  end

  # GenServer callbacks

  @impl true
  def init(agent) do
    {:ok, agent}
  end

  @impl true
  def handle_call({:update_instructions, instructions}, _from, agent) do
    new_agent = %{agent | instructions: instructions}
    {:reply, :ok, new_agent}
  end

  @impl true
  def handle_call({:add_tool, tool}, _from, agent) do
    new_agent = %{agent | tools: [tool | agent.tools]}
    {:reply, :ok, new_agent}
  end

  @impl true
  def handle_call(:get_config, _from, agent) do
    {:reply, agent, agent}
  end

  # Private functions

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
