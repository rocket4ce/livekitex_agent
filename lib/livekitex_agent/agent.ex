defmodule LivekitexAgent.Agent do
  @moduledoc """
  Enhanced agent GenServer that manages voice AI agent configuration and state.

  This module provides:
  - Agent lifecycle management with state transitions
  - Configuration validation and updates
  - Tool registration and management
  - Provider configuration (STT, TTS, LLM, VAD)
  - Performance metrics and monitoring
  - Event system integration
  - Graceful shutdown handling
  """

  use GenServer
  require Logger

  defstruct [
    :agent_id,
    :instructions,
    :tools,
    :llm_config,
    :stt_config,
    :tts_config,
    :vad_config,
    :metadata,
    :created_at,
    :updated_at,
    :state,
    :metrics,
    :event_callbacks,
    :error_count,
    :last_error
  ]

  @type t :: %__MODULE__{
          agent_id: String.t(),
          instructions: String.t(),
          tools: list(atom()),
          llm_config: map(),
          stt_config: map(),
          tts_config: map(),
          vad_config: map(),
          metadata: map(),
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          state: atom(),
          metrics: map(),
          event_callbacks: map(),
          error_count: non_neg_integer(),
          last_error: String.t() | nil
        }

  @type state_transition ::
          {:created, :configured}
          | {:configured, :active}
          | {:active, :inactive}
          | {:inactive, :active}
          | {:configured, :inactive}
          | {atom(), :destroyed}

  @doc """
  Creates a new agent with the given configuration.

  ## Options
  - `:agent_id` - Unique identifier (auto-generated if not provided)
  - `:instructions` - System prompt/instructions for LLM behavior (required)
  - `:tools` - List of function tools available to the agent
  - `:llm_config` - Language model provider configuration
  - `:stt_config` - Speech-to-text provider configuration
  - `:tts_config` - Text-to-speech provider configuration
  - `:vad_config` - Voice activity detection configuration
  - `:metadata` - Custom metadata for agent extensions

  ## Example
      iex> LivekitexAgent.Agent.new(
      ...>   instructions: "You are a helpful assistant",
      ...>   tools: [:get_weather, :search_web],
      ...>   llm_config: %{provider: :openai, model: "gpt-4", temperature: 0.7}
      ...> )
  """
  def new(opts \\ []) do
    now = DateTime.utc_now()

    agent = %__MODULE__{
      agent_id: Keyword.get(opts, :agent_id, generate_id()),
      instructions: Keyword.get(opts, :instructions, ""),
      tools: Keyword.get(opts, :tools, []),
      llm_config: Keyword.get(opts, :llm_config, %{}),
      stt_config: Keyword.get(opts, :stt_config, %{}),
      tts_config: Keyword.get(opts, :tts_config, %{}),
      vad_config: Keyword.get(opts, :vad_config, %{}),
      metadata: Keyword.get(opts, :metadata, %{}),
      created_at: now,
      updated_at: now,
      state: :created,
      metrics: %{},
      event_callbacks: %{},
      error_count: 0,
      last_error: nil
    }

    case validate_agent(agent) do
      :ok -> {:ok, agent}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Starts the agent as a GenServer.
  """
  def start_link(result, opts \\ [])

  def start_link({:ok, agent}, opts) do
    GenServer.start_link(__MODULE__, agent, opts)
  end

  def start_link({:error, reason}, _opts) do
    {:error, reason}
  end

  @doc """
  Updates the agent's configuration and transitions to configured state.
  """
  def configure(pid, config) when is_pid(pid) do
    GenServer.call(pid, {:configure, config})
  end

  @doc """
  Activates the agent, transitioning from configured to active state.
  """
  def activate(pid) when is_pid(pid) do
    GenServer.call(pid, :activate)
  end

  @doc """
  Deactivates the agent, transitioning from active to inactive state.
  """
  def deactivate(pid) when is_pid(pid) do
    GenServer.call(pid, :deactivate)
  end

  @doc """
  Updates the agent's instructions.
  """
  def update_instructions(pid, instructions) when is_pid(pid) do
    GenServer.call(pid, {:update_instructions, instructions})
  end

  @doc """
  Adds a tool to the agent's available tools.
  """
  def add_tool(pid, tool) when is_pid(pid) do
    GenServer.call(pid, {:add_tool, tool})
  end

  @doc """
  Removes a tool from the agent's available tools.
  """
  def remove_tool(pid, tool) when is_pid(pid) do
    GenServer.call(pid, {:remove_tool, tool})
  end

  @doc """
  Registers an event callback for specific events.
  """
  def register_callback(pid, event, callback) when is_pid(pid) do
    GenServer.call(pid, {:register_callback, event, callback})
  end

  @doc """
  Gets the agent's current state and configuration.
  """
  def get_state(pid) when is_pid(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Gets the agent's performance metrics.
  """
  def get_metrics(pid) when is_pid(pid) do
    GenServer.call(pid, :get_metrics)
  end

  @doc """
  Destroys the agent, terminating the GenServer.
  """
  def destroy(pid) when is_pid(pid) do
    GenServer.call(pid, :destroy)
  end

  # GenServer callbacks

  @impl true
  def init(agent) do
    Logger.info("Agent #{agent.agent_id} initialized in state: #{agent.state}")
    {:ok, agent}
  end

  @impl true
  def handle_call({:configure, config}, _from, agent) do
    case transition_state(agent, :configured) do
      {:ok, new_agent} ->
        updated_agent = apply_configuration(new_agent, config)
        {:reply, :ok, updated_agent}

      {:error, reason} ->
        {:reply, {:error, reason}, record_error(agent, reason)}
    end
  end

  @impl true
  def handle_call(:activate, _from, agent) do
    case transition_state(agent, :active) do
      {:ok, new_agent} ->
        trigger_callback(new_agent, :activated)
        {:reply, :ok, new_agent}

      {:error, reason} ->
        {:reply, {:error, reason}, record_error(agent, reason)}
    end
  end

  @impl true
  def handle_call(:deactivate, _from, agent) do
    case transition_state(agent, :inactive) do
      {:ok, new_agent} ->
        trigger_callback(new_agent, :deactivated)
        {:reply, :ok, new_agent}

      {:error, reason} ->
        {:reply, {:error, reason}, record_error(agent, reason)}
    end
  end

  @impl true
  def handle_call({:update_instructions, instructions}, _from, agent) do
    if agent.state == :destroyed do
      {:reply, {:error, :agent_destroyed}, agent}
    else
      case validate_instructions(instructions) do
        :ok ->
          new_agent = %{agent | instructions: instructions, updated_at: DateTime.utc_now()}
          trigger_callback(new_agent, :instructions_updated)
          {:reply, :ok, new_agent}

        {:error, reason} ->
          {:reply, {:error, reason}, record_error(agent, reason)}
      end
    end
  end

  @impl true
  def handle_call({:add_tool, tool}, _from, agent) do
    if agent.state == :destroyed do
      {:reply, {:error, :agent_destroyed}, agent}
    else
      case validate_tool(tool) do
        :ok ->
          if tool in agent.tools do
            {:reply, {:error, :tool_already_exists}, agent}
          else
            new_agent = %{agent | tools: [tool | agent.tools], updated_at: DateTime.utc_now()}
            trigger_callback(new_agent, :tool_added)
            {:reply, :ok, new_agent}
          end

        {:error, reason} ->
          {:reply, {:error, reason}, record_error(agent, reason)}
      end
    end
  end

  @impl true
  def handle_call({:remove_tool, tool}, _from, agent) do
    if agent.state == :destroyed do
      {:reply, {:error, :agent_destroyed}, agent}
    else
      new_tools = List.delete(agent.tools, tool)
      new_agent = %{agent | tools: new_tools, updated_at: DateTime.utc_now()}
      trigger_callback(new_agent, :tool_removed)
      {:reply, :ok, new_agent}
    end
  end

  @impl true
  def handle_call({:register_callback, event, callback}, _from, agent) do
    if agent.state == :destroyed do
      {:reply, {:error, :agent_destroyed}, agent}
    else
      new_callbacks = Map.put(agent.event_callbacks, event, callback)
      new_agent = %{agent | event_callbacks: new_callbacks}
      {:reply, :ok, new_agent}
    end
  end

  @impl true
  def handle_call(:get_state, _from, agent) do
    {:reply, agent, agent}
  end

  @impl true
  def handle_call(:get_metrics, _from, agent) do
    {:reply, agent.metrics, agent}
  end

  @impl true
  def handle_call(:destroy, _from, agent) do
    case transition_state(agent, :destroyed) do
      {:ok, new_agent} ->
        trigger_callback(new_agent, :destroyed)
        {:stop, :normal, :ok, new_agent}

      {:error, reason} ->
        {:reply, {:error, reason}, agent}
    end
  end

  @impl true
  def terminate(reason, agent) do
    Logger.info("Agent #{agent.agent_id} terminating with reason: #{inspect(reason)}")
    :ok
  end

  # Private functions

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp validate_agent(agent) do
    with :ok <- validate_agent_id(agent.agent_id),
         :ok <- validate_instructions(agent.instructions),
         :ok <- validate_tools(agent.tools) do
      :ok
    end
  end

  defp validate_agent_id(agent_id) do
    cond do
      is_nil(agent_id) or agent_id == "" ->
        {:error, :agent_id_required}

      String.length(agent_id) > 255 ->
        {:error, :agent_id_too_long}

      true ->
        :ok
    end
  end

  defp validate_instructions(instructions) do
    cond do
      is_nil(instructions) or instructions == "" ->
        {:error, :instructions_required}

      String.length(instructions) > 10_000 ->
        {:error, :instructions_too_long}

      true ->
        :ok
    end
  end

  defp validate_tools(tools) when is_list(tools) do
    Enum.reduce_while(tools, :ok, fn tool, :ok ->
      case validate_tool(tool) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_tools(_), do: {:error, :tools_must_be_list}

  defp validate_tool(tool) when is_atom(tool), do: :ok
  defp validate_tool(_), do: {:error, :tool_must_be_atom}

  defp transition_state(agent, new_state) do
    if valid_transition?(agent.state, new_state) do
      {:ok, %{agent | state: new_state, updated_at: DateTime.utc_now()}}
    else
      {:error, {:invalid_transition, agent.state, new_state}}
    end
  end

  defp valid_transition?(current, target) do
    case {current, target} do
      {:created, :configured} -> true
      {:configured, :active} -> true
      {:configured, :inactive} -> true
      {:active, :inactive} -> true
      {:inactive, :active} -> true
      {_, :destroyed} -> true
      _ -> false
    end
  end

  defp apply_configuration(agent, config) do
    %{
      agent
      | llm_config: Map.get(config, :llm_config, agent.llm_config),
        stt_config: Map.get(config, :stt_config, agent.stt_config),
        tts_config: Map.get(config, :tts_config, agent.tts_config),
        vad_config: Map.get(config, :vad_config, agent.vad_config),
        metadata: Map.merge(agent.metadata, Map.get(config, :metadata, %{})),
        updated_at: DateTime.utc_now()
    }
  end

  defp record_error(agent, error) do
    %{
      agent
      | error_count: agent.error_count + 1,
        last_error: to_string(error),
        updated_at: DateTime.utc_now()
    }
  end

  defp trigger_callback(agent, event) do
    case Map.get(agent.event_callbacks, event) do
      nil ->
        :ok

      callback when is_function(callback, 2) ->
        try do
          callback.(agent, event)
        rescue
          e -> Logger.error("Error in agent callback: #{inspect(e)}")
        end

      _ ->
        Logger.warning("Invalid callback for event: #{event}")
    end
  end
end
