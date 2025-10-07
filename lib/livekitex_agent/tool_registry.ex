defmodule LivekitexAgent.ToolRegistry do
  @moduledoc """
  GenServer that manages dynamic registration and discovery of function tools.

  The ToolRegistry provides:
  - Dynamic tool registration and deregistration
  - Tool discovery by name or metadata
  - Tool validation and schema generation
  - Performance metrics for tool usage
  - Event notifications for registry changes
  """

  use GenServer
  require Logger

  @table_name :livekitex_agent_tools

  defstruct [
    :table_ref,
    :metrics,
    :event_callbacks,
    :validation_enabled
  ]

  @type tool_definition :: %{
    name: atom(),
    module: module(),
    function: atom(),
    schema: map(),
    metadata: map(),
    registered_at: DateTime.t()
  }

  @type t :: %__MODULE__{
    table_ref: :ets.tid(),
    metrics: map(),
    event_callbacks: map(),
    validation_enabled: boolean()
  }

  ## Client API

  @doc """
  Starts the tool registry GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a function tool with the registry.

  ## Parameters
  - `name` - Unique atom identifier for the tool
  - `module` - Module containing the tool function
  - `function` - Function name (atom)
  - `schema` - OpenAI-compatible function schema
  - `metadata` - Additional metadata (optional)

  ## Example
      iex> LivekitexAgent.ToolRegistry.register_tool(
      ...>   :get_weather,
      ...>   WeatherTools,
      ...>   :get_weather,
      ...>   %{
      ...>     type: "function",
      ...>     function: %{
      ...>       name: "get_weather",
      ...>       description: "Get current weather"
      ...>     }
      ...>   }
      ...> )
      :ok
  """
  def register_tool(name, module, function, schema, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:register_tool, name, module, function, schema, metadata})
  end

  @doc """
  Unregisters a tool from the registry.
  """
  def unregister_tool(name) do
    GenServer.call(__MODULE__, {:unregister_tool, name})
  end

  @doc """
  Gets a tool definition by name.
  """
  def get_tool(name) do
    GenServer.call(__MODULE__, {:get_tool, name})
  end

  @doc """
  Lists all registered tools.
  """
  def list_tools do
    GenServer.call(__MODULE__, :list_tools)
  end

  @doc """
  Searches for tools by metadata criteria.
  """
  def search_tools(criteria) do
    GenServer.call(__MODULE__, {:search_tools, criteria})
  end

  @doc """
  Executes a tool with given parameters.
  """
  def execute_tool(name, params, context \\ %{}) do
    GenServer.call(__MODULE__, {:execute_tool, name, params, context})
  end

  @doc """
  Gets tool execution metrics.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Registers an event callback for registry changes.
  """
  def register_callback(event, callback) do
    GenServer.call(__MODULE__, {:register_callback, event, callback})
  end

  @doc """
  Validates if a tool is properly registered and callable.
  """
  def validate_tool(name) do
    GenServer.call(__MODULE__, {:validate_tool, name})
  end

  ## Legacy API compatibility (for backward compatibility)

  @doc """
  Legacy register function - converts to new format.
  """
  def register(tool_definition) when is_map(tool_definition) do
    name = Map.get(tool_definition, :name)
    module = Map.get(tool_definition, :module)
    function = Map.get(tool_definition, :function, :call)
    schema = Map.get(tool_definition, :schema, %{})
    metadata = Map.get(tool_definition, :metadata, %{})

    register_tool(name, module, function, schema, metadata)
  end

  @doc """
  Legacy get function.
  """
  def get(tool_name) do
    case get_tool(tool_name) do
      {:ok, tool_def} -> tool_def
      {:error, :tool_not_found} -> nil
    end
  end

  @doc """
  Legacy get_all function.
  """
  def get_all do
    list_tools()
    |> Enum.map(fn tool_def -> {tool_def.name, tool_def} end)
    |> Enum.into(%{})
  end

  @doc """
  Legacy unregister function.
  """
  def unregister(tool_name) do
    unregister_tool(tool_name)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    table_ref = :ets.new(@table_name, [:set, :protected, :named_table])

    state = %__MODULE__{
      table_ref: table_ref,
      metrics: %{
        total_tools: 0,
        total_executions: 0,
        average_execution_time: 0.0,
        errors: 0
      },
      event_callbacks: %{},
      validation_enabled: Keyword.get(opts, :validation_enabled, true)
    }

    Logger.info("ToolRegistry started with table: #{inspect(table_ref)}")
    {:ok, state}
  end

  @impl true
  def handle_call({:register_tool, name, module, function, schema, metadata}, _from, state) do
    case validate_tool_registration(name, module, function, schema, state) do
      :ok ->
        tool_def = %{
          name: name,
          module: module,
          function: function,
          schema: schema,
          metadata: metadata,
          registered_at: DateTime.utc_now()
        }

        :ets.insert(@table_name, {name, tool_def})

        new_metrics = update_in(state.metrics, [:total_tools], &(&1 + 1))
        new_state = %{state | metrics: new_metrics}

        trigger_callback(new_state, :tool_registered, {name, tool_def})
        Logger.info("Tool registered: #{name}")

        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.warning("Failed to register tool #{name}: #{reason}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unregister_tool, name}, _from, state) do
    case :ets.lookup(@table_name, name) do
      [{^name, tool_def}] ->
        :ets.delete(@table_name, name)

        new_metrics = update_in(state.metrics, [:total_tools], &(&1 - 1))
        new_state = %{state | metrics: new_metrics}

        trigger_callback(new_state, :tool_unregistered, {name, tool_def})
        Logger.info("Tool unregistered: #{name}")

        {:reply, :ok, new_state}

      [] ->
        {:reply, {:error, :tool_not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_tool, name}, _from, state) do
    case :ets.lookup(@table_name, name) do
      [{^name, tool_def}] -> {:reply, {:ok, tool_def}, state}
      [] -> {:reply, {:error, :tool_not_found}, state}
    end
  end

  @impl true
  def handle_call(:list_tools, _from, state) do
    tools = :ets.tab2list(@table_name)
    |> Enum.map(fn {_name, tool_def} -> tool_def end)

    {:reply, tools, state}
  end

  @impl true
  def handle_call({:search_tools, criteria}, _from, state) do
    tools = :ets.tab2list(@table_name)
    |> Enum.map(fn {_name, tool_def} -> tool_def end)
    |> Enum.filter(&matches_criteria?(&1, criteria))

    {:reply, tools, state}
  end

  @impl true
  def handle_call({:execute_tool, name, params, context}, _from, state) do
    start_time = System.monotonic_time(:millisecond)

    result = case :ets.lookup(@table_name, name) do
      [{^name, tool_def}] ->
        execute_tool_function(tool_def, params, context)

      [] ->
        {:error, :tool_not_found}
    end

    execution_time = System.monotonic_time(:millisecond) - start_time
    new_state = update_execution_metrics(state, result, execution_time)

    trigger_callback(new_state, :tool_executed, {name, result, execution_time})

    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  @impl true
  def handle_call({:register_callback, event, callback}, _from, state) do
    new_callbacks = Map.put(state.event_callbacks, event, callback)
    new_state = %{state | event_callbacks: new_callbacks}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:validate_tool, name}, _from, state) do
    case :ets.lookup(@table_name, name) do
      [{^name, tool_def}] ->
        result = validate_tool_callable(tool_def)
        {:reply, result, state}

      [] ->
        {:reply, {:error, :tool_not_found}, state}
    end
  end

  # Legacy API handlers
  @impl true
  def handle_call({:register, tool_definition}, from, state) do
    handle_call({:register_tool,
      Map.get(tool_definition, :name),
      Map.get(tool_definition, :module),
      Map.get(tool_definition, :function, :call),
      Map.get(tool_definition, :schema, %{}),
      Map.get(tool_definition, :metadata, %{})
    }, from, state)
  end

  @impl true
  def handle_call({:get, tool_name}, _from, state) do
    case :ets.lookup(@table_name, tool_name) do
      [{^tool_name, tool_def}] -> {:reply, tool_def, state}
      [] -> {:reply, nil, state}
    end
  end

  @impl true
  def handle_call(:get_all, _from, state) do
    tools = :ets.tab2list(@table_name)
    |> Enum.map(fn {name, tool_def} -> {name, tool_def} end)
    |> Enum.into(%{})

    {:reply, tools, state}
  end

  @impl true
  def handle_call({:unregister, tool_name}, from, state) do
    handle_call({:unregister_tool, tool_name}, from, state)
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("ToolRegistry terminating with reason: #{inspect(reason)}")
    :ets.delete(@table_name)
    :ok
  end

  ## Private Functions

  defp validate_tool_registration(name, module, function, schema, state) do
    with :ok <- validate_tool_name(name),
         :ok <- validate_module_function(module, function),
         :ok <- validate_schema(schema, state.validation_enabled),
         :ok <- check_tool_not_exists(name) do
      :ok
    end
  end

  defp validate_tool_name(name) when is_atom(name), do: :ok
  defp validate_tool_name(_), do: {:error, :invalid_tool_name}

  defp validate_module_function(module, function) do
    if Code.ensure_loaded?(module) and function_exported?(module, function, 2) do
      :ok
    else
      {:error, :module_function_not_found}
    end
  end

  defp validate_schema(schema, true) when is_map(schema) do
    required_keys = ["type", "function"]
    if Enum.all?(required_keys, &Map.has_key?(schema, &1)) do
      :ok
    else
      {:error, :invalid_schema}
    end
  end

  defp validate_schema(_, false), do: :ok
  defp validate_schema(_, _), do: {:error, :invalid_schema}

  defp check_tool_not_exists(name) do
    case :ets.lookup(@table_name, name) do
      [] -> :ok
      _ -> {:error, :tool_already_exists}
    end
  end

  defp matches_criteria?(tool_def, criteria) do
    Enum.all?(criteria, fn {key, value} ->
      case Map.get(tool_def, key) do
        ^value -> true
        metadata when key == :metadata and is_map(metadata) ->
          Map.get(metadata, value) != nil
        _ -> false
      end
    end)
  end

  defp execute_tool_function(tool_def, params, context) do
    try do
      apply(tool_def.module, tool_def.function, [params, context])
    rescue
      e ->
        Logger.error("Tool execution error: #{inspect(e)}")
        {:error, {:execution_failed, e.message}}
    catch
      :exit, reason ->
        Logger.error("Tool execution exit: #{inspect(reason)}")
        {:error, {:execution_exit, reason}}
    end
  end

  defp update_execution_metrics(state, result, execution_time) do
    metrics = state.metrics

    new_metrics = %{
      metrics |
      total_executions: metrics.total_executions + 1,
      average_execution_time: calculate_average_time(
        metrics.average_execution_time,
        execution_time,
        metrics.total_executions + 1
      ),
      errors: metrics.errors + if(match?({:error, _}, result), do: 1, else: 0)
    }

    %{state | metrics: new_metrics}
  end

  defp calculate_average_time(current_avg, new_time, total_count) do
    (current_avg * (total_count - 1) + new_time) / total_count
  end

  defp validate_tool_callable(tool_def) do
    case Code.ensure_loaded(tool_def.module) do
      {:module, _} ->
        if function_exported?(tool_def.module, tool_def.function, 2) do
          :ok
        else
          {:error, :function_not_exported}
        end

      {:error, reason} ->
        {:error, {:module_not_loadable, reason}}
    end
  end

  defp trigger_callback(state, event, data) do
    case Map.get(state.event_callbacks, event) do
      nil -> :ok
      callback when is_function(callback, 2) ->
        try do
          callback.(event, data)
        rescue
          e -> Logger.error("Error in tool registry callback: #{inspect(e)}")
        end
      _ -> Logger.warning("Invalid callback for event: #{event}")
    end
  end
end
