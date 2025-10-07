defmodule LivekitexAgent.FunctionTool do
  @moduledoc """
  Decorator and utilities to register Elixir functions as tools that the LLM can call.

  FunctionTool provides:
  - Auto-discovery of tool functions through attributes
  - Automatic schema generation from function signatures
  - Parameter handling and conversion to LLM-compatible format
  - Raw tools support for custom function descriptions
  - Tool registry management
  """

  @doc """
  Defines a function tool that can be called by the LLM.

  ## Usage

  Use the `@tool` attribute to mark functions as available tools:

      defmodule MyTools do
        use LivekitexAgent.FunctionTool

        @tool "Get weather information for a location"
        @spec get_weather(String.t()) :: String.t()
        def get_weather(location) do
          "Weather in " <> location <> ": Sunny, 25°C"
        end

        @tool "Calculate the sum of two numbers"
        @spec add_numbers(number(), number()) :: number()
        def add_numbers(a, b) do
          a + b
        end
      end

  ## With RunContext

  Tools can accept a RunContext as the last parameter:

      @tool "Search for information"
      @spec search_web(String.t(), LivekitexAgent.RunContext.t()) :: String.t()
      def search_web(query, context) do
        LivekitexAgent.RunContext.log_info(context, "Searching for: " <> query)
        # ... perform search
        "Search results for " <> query
      end
  """

  defmacro __using__(_opts) do
    quote do
      import LivekitexAgent.FunctionTool
      Module.register_attribute(__MODULE__, :tools, accumulate: true)

      @before_compile LivekitexAgent.FunctionTool
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def __tools__ do
        tools = Module.get_attribute(__MODULE__, :tools) || []
        build_tool_definitions(__MODULE__, tools)
      end
    end
  end

  @doc """
  Marks a function as a tool with an optional description.
  """
  defmacro tool(description) do
    quote do
      @tools unquote(description)
    end
  end

  @doc """
  Registers a module's tools in the global tool registry with dynamic loading support.
  """
  def register_module(module, opts \\ []) do
    if function_exported?(module, :__tools__, 0) do
      tools = module.__tools__()
      auto_reload = Keyword.get(opts, :auto_reload, false)
      namespace = Keyword.get(opts, :namespace)

      results =
        Enum.map(tools, fn tool ->
          enhanced_tool = enhance_tool_definition(tool, module, opts)
          register_tool_with_options(enhanced_tool, auto_reload, namespace)
        end)

      # Check for any failures
      case Enum.find(results, &match?({:error, _}, &1)) do
        nil -> {:ok, length(tools)}
        error -> error
      end
    else
      raise "Module #{module} does not define any tools. Use `use LivekitexAgent.FunctionTool` and @tool attributes."
    end
  end

  @doc """
  Registers a single tool in the global registry with enhanced options.
  """
  def register_tool(tool_definition, opts \\ []) do
    auto_reload = Keyword.get(opts, :auto_reload, false)
    namespace = Keyword.get(opts, :namespace)

    register_tool_with_options(tool_definition, auto_reload, namespace)
  end

  @doc """
  Discovers and registers all tools from a given directory or application.
  """
  def discover_and_register_tools(search_path, opts \\ []) do
    pattern = Keyword.get(opts, :pattern, "**/*_tools.ex")
    auto_reload = Keyword.get(opts, :auto_reload, false)

    search_path
    |> Path.join(pattern)
    |> Path.wildcard()
    |> Enum.map(&extract_module_from_file/1)
    |> Enum.filter(& &1)
    |> Enum.map(fn module ->
      try do
        register_module(module, auto_reload: auto_reload)
      rescue
        error ->
          Logger.warning("Failed to register tools from #{module}: #{inspect(error)}")
          {:error, error}
      end
    end)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> length()
  end

  @doc """
  Hot-reloads a module's tools if auto-reload is enabled.
  """
  def reload_module_tools(module) do
    # First unregister existing tools
    case get_module_tools(module) do
      {:ok, existing_tools} ->
        Enum.each(existing_tools, fn tool ->
          LivekitexAgent.ToolRegistry.unregister_tool(tool.name)
        end)

      _ ->
        :ok
    end

    # Re-register with current definitions
    register_module(module, auto_reload: true)
  end

  defp register_tool_with_options(tool_definition, auto_reload, namespace) do
    enhanced_definition =
      tool_definition
      |> add_namespace(namespace)
      |> add_auto_reload_metadata(auto_reload)
      |> add_openai_schema()

    LivekitexAgent.ToolRegistry.register_tool(
      String.to_atom(enhanced_definition.name),
      enhanced_definition.module,
      enhanced_definition.function,
      enhanced_definition.schema,
      enhanced_definition.metadata
    )
  end

  defp enhance_tool_definition(tool, module, opts) do
    namespace = Keyword.get(opts, :namespace)

    tool
    |> Map.put(:module, module)
    |> add_validation_metadata()
    |> add_performance_metadata()
  end

  defp add_namespace(tool, nil), do: tool

  defp add_namespace(tool, namespace) do
    namespaced_name = "#{namespace}.#{tool.name}"
    %{tool | name: namespaced_name}
  end

  defp add_auto_reload_metadata(tool, false), do: tool

  defp add_auto_reload_metadata(tool, true) do
    metadata = Map.put(tool.metadata || %{}, :auto_reload, true)
    %{tool | metadata: metadata}
  end

  defp add_openai_schema(tool) do
    schema = to_openai_format(tool)
    %{tool | schema: schema}
  end

  defp add_validation_metadata(tool) do
    metadata =
      (tool.metadata || %{})
      |> Map.put(:has_validation, true)
      |> Map.put(:parameter_count, length(tool.parameters))
      |> Map.put(:required_params, extract_required_parameters(tool.parameters))

    %{tool | metadata: metadata}
  end

  defp add_performance_metadata(tool) do
    metadata =
      (tool.metadata || %{})
      |> Map.put(:performance_tracked, true)
      |> Map.put(:registered_at, DateTime.utc_now())

    %{tool | metadata: metadata}
  end

  defp extract_module_from_file(file_path) do
    try do
      # Simple heuristic to extract module name from file path
      file_path
      |> Path.basename(".ex")
      |> String.split("_")
      |> Enum.map(&String.capitalize/1)
      |> Enum.join("")
      |> String.to_existing_atom()
    rescue
      _ -> nil
    end
  end

  defp get_module_tools(module) do
    case LivekitexAgent.ToolRegistry.list_tools() do
      {:ok, tools} ->
        module_tools = Enum.filter(tools, &(&1.module == module))
        {:ok, module_tools}

      error ->
        error
    end
  end

  @doc """
  Gets all registered tools.
  """
  def get_all_tools do
    LivekitexAgent.ToolRegistry.get_all()
  end

  @doc """
  Gets a tool by name.
  """
  def get_tool(name) do
    LivekitexAgent.ToolRegistry.get(name)
  end

  @doc """
  Executes a tool with the given arguments and context.

  Options:
  - `:timeout` - Execution timeout in milliseconds (default: 60_000)
  - `:retry_attempts` - Number of retry attempts on failure (default: 0)
  - `:circuit_breaker` - Enable circuit breaker pattern (default: true)
  """
  def execute_tool(tool_name, arguments, context \\ nil, opts \\ []) do
    case get_tool(tool_name) do
      nil ->
        {:error, :tool_not_found}

      tool ->
        execute_tool_definition(tool, arguments, context, opts)
    end
  end

  @doc """
  Executes a tool with enhanced error handling and monitoring.
  """
  def execute_tool_safely(tool_name, arguments, context \\ nil, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 60_000)
    retry_attempts = Keyword.get(opts, :retry_attempts, 0)

    execution_start = System.monotonic_time(:millisecond)

    result =
      if retry_attempts > 0 do
        execute_with_retry(tool_name, arguments, context, opts, retry_attempts)
      else
        execute_tool(tool_name, arguments, context, opts)
      end

    execution_duration = System.monotonic_time(:millisecond) - execution_start

    # Log execution metrics
    log_tool_execution(tool_name, result, execution_duration, context)

    result
  end

  defp execute_with_retry(tool_name, arguments, context, opts, attempts) when attempts > 0 do
    case execute_tool(tool_name, arguments, context, opts) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} when attempts > 1 ->
        # Log retry attempt
        if context do
          LivekitexAgent.RunContext.log_warning(
            context,
            "Tool execution failed, retrying: #{tool_name}",
            %{error: reason, attempts_remaining: attempts - 1}
          )
        end

        # Brief backoff before retry
        :timer.sleep(100 * (4 - attempts))
        execute_with_retry(tool_name, arguments, context, opts, attempts - 1)

      error ->
        error
    end
  end

  @doc """
  Creates a tool definition from a function.
  """
  def create_tool_definition(module, function_name, arity, description \\ nil) do
    case Code.Typespec.fetch_specs(module) do
      {:ok, specs} ->
        spec = find_function_spec(specs, function_name, arity)

        %{
          name: to_string(function_name),
          description: description || generate_description(function_name),
          module: module,
          function: function_name,
          arity: arity,
          parameters: extract_parameters(spec),
          return_type: extract_return_type(spec)
        }

      :error ->
        # Create basic definition without type information
        %{
          name: to_string(function_name),
          description: description || generate_description(function_name),
          module: module,
          function: function_name,
          arity: arity,
          parameters: generate_basic_parameters(arity),
          return_type: "any"
        }
    end
  end

  @doc """
  Converts tool definitions to OpenAI function format.
  """
  def to_openai_format(tool_definitions) when is_list(tool_definitions) do
    Enum.map(tool_definitions, &to_openai_format/1)
  end

  def to_openai_format(tool_definition) do
    %{
      type: "function",
      function: %{
        name: tool_definition.name,
        description: tool_definition.description,
        parameters: %{
          type: "object",
          properties: build_openai_properties(tool_definition.parameters),
          required: extract_required_parameters(tool_definition.parameters)
        }
      }
    }
  end

  @doc """
  Validates tool arguments against the tool definition.
  """
  def validate_arguments(tool_definition, arguments) do
    required_params = extract_required_parameters(tool_definition.parameters)
    provided_params = Map.keys(arguments)

    # Check for missing required parameters
    missing = required_params -- provided_params

    if length(missing) > 0 do
      {:error, {:missing_parameters, missing}}
    else
      # Validate parameter types
      validate_parameter_types(tool_definition.parameters, arguments)
    end
  end

  # Private functions

  def build_tool_definitions(module, descriptions) do
    # Get all exported functions from the module
    functions = module.module_info(:functions)

    # Filter functions that have tool descriptions
    tool_functions =
      functions
      |> Enum.filter(fn {name, _arity} ->
        # Skip special functions
        name not in [:__info__, :__tools__, :module_info]
      end)
      |> Enum.zip(descriptions)
      |> Enum.map(fn {{function_name, arity}, description} ->
        create_tool_definition(module, function_name, arity, description)
      end)

    tool_functions
  end

  defp execute_tool_definition(tool, arguments, context, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 60_000)

    case validate_and_convert_arguments(tool, arguments) do
      {:ok, converted_args} ->
        do_execute_tool_with_timeout(tool, converted_args, context, timeout)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_execute_tool_with_timeout(tool, arguments, context, timeout) do
    task = Task.async(fn -> do_execute_tool(tool, arguments, context) end)

    try do
      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, result} ->
          result

        nil ->
          {:error, {:timeout, timeout}}
      end
    rescue
      error ->
        Task.shutdown(task, :brutal_kill)
        {:error, {:task_error, error}}
    end
  end

  defp do_execute_tool(tool, arguments, context) do
    # Convert arguments to function parameters
    args = prepare_arguments(tool, arguments, context)

    try do
      result = apply(tool.module, tool.function, args)
      {:ok, result}
    rescue
      error ->
        {:error, {:execution_error, error}}
    end
  end

  defp prepare_arguments(tool, arguments, context) do
    # Sort parameters by their order in the function signature
    sorted_params = Enum.sort_by(tool.parameters, & &1.position)

    # Build argument list, handling context parameter specially
    args =
      sorted_params
      |> Enum.map(fn param ->
        case param.name do
          "context" -> context
          name -> Map.get(arguments, name)
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Ensure context is added if function expects it but not provided
    if has_context_parameter?(tool) and context != nil and !context_in_args?(args, context) do
      args ++ [context]
    else
      args
    end
  end

  defp context_in_args?(args, context) do
    Enum.any?(args, &(&1 == context))
  end

  defp log_tool_execution(tool_name, result, duration, context) do
    log_data = %{
      tool: tool_name,
      duration_ms: duration,
      success: match?({:ok, _}, result)
    }

    case result do
      {:ok, _} ->
        if context do
          LivekitexAgent.RunContext.log_info(context, "Tool executed successfully", log_data)
        else
          Logger.info("Tool executed successfully: #{tool_name}", log_data)
        end

      {:error, reason} ->
        error_data = Map.put(log_data, :error, inspect(reason))

        if context do
          LivekitexAgent.RunContext.log_error(context, "Tool execution failed", error_data)
        else
          Logger.error("Tool execution failed: #{tool_name}", error_data)
        end
    end
  end

  defp has_context_parameter?(tool) do
    Enum.any?(tool.parameters, &(&1.name == "context"))
  end

  defp find_function_spec(specs, function_name, arity) do
    Enum.find(specs, fn
      {{^function_name, ^arity}, _spec} -> true
      _ -> false
    end)
  end

  defp extract_parameters(nil), do: []

  defp extract_parameters({{_name, _arity}, spec_list}) do
    # Extract parameters from the first spec
    case spec_list do
      [{:type, _, :fun, [{:type, _, :product, param_types}, _return_type]}] ->
        param_types
        |> Enum.with_index()
        |> Enum.map(fn {type, index} ->
          %{
            name: infer_parameter_name(type, index),
            type: format_type(type),
            position: index,
            required: !is_optional_type?(type),
            description: generate_parameter_description(type, index)
          }
        end)

      _ ->
        []
    end
  end

  defp extract_return_type(nil), do: "any"

  defp extract_return_type({{_name, _arity}, spec_list}) do
    case spec_list do
      [{:type, _, :fun, [_param_types, return_type]}] ->
        format_type(return_type)

      _ ->
        "any"
    end
  end

  defp format_type({:type, _, :binary, []}), do: "string"
  defp format_type({:type, _, :integer, []}), do: "integer"
  defp format_type({:type, _, :float, []}), do: "number"
  defp format_type({:type, _, :boolean, []}), do: "boolean"
  defp format_type({:type, _, :list, _}), do: "array"
  defp format_type({:type, _, :map, _}), do: "object"
  defp format_type({:user_type, _, type_name, _}), do: to_string(type_name)
  defp format_type(_), do: "any"

  defp generate_basic_parameters(arity) do
    for i <- 0..(arity - 1) do
      %{
        name: "param_#{i}",
        type: "any",
        position: i,
        required: true
      }
    end
  end

  defp generate_description(function_name) do
    function_name
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp infer_parameter_name({:var, _, name}, _index) when is_atom(name) do
    to_string(name)
  end

  defp infer_parameter_name({:type, _, :binary, []}, _index), do: "text"
  defp infer_parameter_name({:type, _, :integer, []}, _index), do: "number"
  defp infer_parameter_name({:type, _, :float, []}, _index), do: "value"
  defp infer_parameter_name({:type, _, :boolean, []}, _index), do: "flag"
  defp infer_parameter_name({:type, _, :list, _}, _index), do: "items"
  defp infer_parameter_name({:type, _, :map, _}, _index), do: "data"
  defp infer_parameter_name({:user_type, _, type_name, _}, _index), do: to_string(type_name)
  defp infer_parameter_name(_, index), do: "param_#{index}"

  defp is_optional_type?({:type, _, :union, types}) do
    Enum.any?(types, &match?({:atom, _, nil}, &1))
  end

  defp is_optional_type?(_), do: false

  defp generate_parameter_description({:type, _, :binary, []}, _), do: "Text string parameter"
  defp generate_parameter_description({:type, _, :integer, []}, _), do: "Integer number parameter"

  defp generate_parameter_description({:type, _, :float, []}, _),
    do: "Floating point number parameter"

  defp generate_parameter_description({:type, _, :boolean, []}, _),
    do: "Boolean true/false parameter"

  defp generate_parameter_description({:type, _, :list, _}, _), do: "List of items parameter"
  defp generate_parameter_description({:type, _, :map, _}, _), do: "Map/object parameter"

  defp generate_parameter_description({:user_type, _, type_name, _}, _),
    do: "#{type_name} parameter"

  defp generate_parameter_description(_, index), do: "Parameter #{index}"

  defp build_openai_properties(parameters) do
    parameters
    |> Enum.reject(&(&1.name == "context"))
    |> Enum.reduce(%{}, fn param, acc ->
      property = %{
        type: openai_type(param.type),
        description: param[:description] || "Parameter #{param.name}"
      }

      # Add additional schema constraints based on type
      property = add_openai_constraints(property, param)

      Map.put(acc, param.name, property)
    end)
  end

  defp add_openai_constraints(property, %{type: "string"} = param) do
    property
    |> maybe_add_enum(param)
    |> maybe_add_pattern(param)
  end

  defp add_openai_constraints(property, %{type: "integer"} = param) do
    property
    |> maybe_add_minimum(param)
    |> maybe_add_maximum(param)
  end

  defp add_openai_constraints(property, %{type: "number"} = param) do
    property
    |> maybe_add_minimum(param)
    |> maybe_add_maximum(param)
  end

  defp add_openai_constraints(property, %{type: "array"} = param) do
    property
    |> maybe_add_items_schema(param)
    |> maybe_add_min_items(param)
    |> maybe_add_max_items(param)
  end

  defp add_openai_constraints(property, _param), do: property

  defp maybe_add_enum(property, %{enum: enum}) when is_list(enum) do
    Map.put(property, :enum, enum)
  end

  defp maybe_add_enum(property, _), do: property

  defp maybe_add_pattern(property, %{pattern: pattern}) when is_binary(pattern) do
    Map.put(property, :pattern, pattern)
  end

  defp maybe_add_pattern(property, _), do: property

  defp maybe_add_minimum(property, %{minimum: min}) when is_number(min) do
    Map.put(property, :minimum, min)
  end

  defp maybe_add_minimum(property, _), do: property

  defp maybe_add_maximum(property, %{maximum: max}) when is_number(max) do
    Map.put(property, :maximum, max)
  end

  defp maybe_add_maximum(property, _), do: property

  defp maybe_add_items_schema(property, %{items: items_schema}) when is_map(items_schema) do
    Map.put(property, :items, items_schema)
  end

  defp maybe_add_items_schema(property, _), do: property

  defp maybe_add_min_items(property, %{min_items: min}) when is_integer(min) do
    Map.put(property, :minItems, min)
  end

  defp maybe_add_min_items(property, _), do: property

  defp maybe_add_max_items(property, %{max_items: max}) when is_integer(max) do
    Map.put(property, :maxItems, max)
  end

  defp maybe_add_max_items(property, _), do: property

  defp extract_required_parameters(parameters) do
    parameters
    |> Enum.filter(&(&1.required and &1.name != "context"))
    |> Enum.map(& &1.name)
  end

  defp openai_type("string"), do: "string"
  defp openai_type("integer"), do: "integer"
  defp openai_type("number"), do: "number"
  defp openai_type("float"), do: "number"
  defp openai_type("boolean"), do: "boolean"
  defp openai_type("array"), do: "array"
  defp openai_type("object"), do: "object"
  defp openai_type(_), do: "string"

  @doc """
  Validates and converts arguments to proper types based on tool definition.
  """
  def validate_and_convert_arguments(tool_definition, arguments) do
    case validate_arguments(tool_definition, arguments) do
      :ok ->
        convert_arguments(tool_definition, arguments)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Converts arguments to the expected types based on parameter definitions.
  """
  def convert_arguments(tool_definition, arguments) do
    converted =
      tool_definition.parameters
      |> Enum.reduce_while({:ok, %{}}, fn param, {:ok, acc} ->
        case convert_parameter(param, Map.get(arguments, param.name)) do
          {:ok, converted_value} ->
            {:cont, {:ok, Map.put(acc, param.name, converted_value)}}

          {:error, reason} ->
            {:halt, {:error, {:conversion_error, param.name, reason}}}
        end
      end)

    case converted do
      {:ok, converted_args} -> {:ok, converted_args}
      error -> error
    end
  end

  defp convert_parameter(%{name: "context"}, value), do: {:ok, value}

  defp convert_parameter(%{type: "string"}, value) when is_binary(value), do: {:ok, value}
  defp convert_parameter(%{type: "string"}, value), do: {:ok, to_string(value)}

  defp convert_parameter(%{type: "integer"}, value) when is_integer(value), do: {:ok, value}

  defp convert_parameter(%{type: "integer"}, value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_integer}
    end
  end

  defp convert_parameter(%{type: "integer"}, value) when is_float(value), do: {:ok, trunc(value)}

  defp convert_parameter(%{type: "number"}, value) when is_number(value), do: {:ok, value}

  defp convert_parameter(%{type: "number"}, value) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} ->
        {:ok, float}

      _ ->
        case Integer.parse(value) do
          {int, ""} -> {:ok, int}
          _ -> {:error, :invalid_number}
        end
    end
  end

  defp convert_parameter(%{type: "boolean"}, value) when is_boolean(value), do: {:ok, value}
  defp convert_parameter(%{type: "boolean"}, "true"), do: {:ok, true}
  defp convert_parameter(%{type: "boolean"}, "false"), do: {:ok, false}
  defp convert_parameter(%{type: "boolean"}, 1), do: {:ok, true}
  defp convert_parameter(%{type: "boolean"}, 0), do: {:ok, false}

  defp convert_parameter(%{type: "array"}, value) when is_list(value), do: {:ok, value}

  defp convert_parameter(%{type: "array"}, value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, list} when is_list(list) -> {:ok, list}
      _ -> {:error, :invalid_array}
    end
  end

  defp convert_parameter(%{type: "object"}, value) when is_map(value), do: {:ok, value}

  defp convert_parameter(%{type: "object"}, value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> {:error, :invalid_object}
    end
  end

  defp convert_parameter(_param, nil), do: {:ok, nil}
  defp convert_parameter(_param, value), do: {:ok, value}

  defp validate_parameter_types(parameters, arguments) do
    # Enhanced type validation with better error reporting
    Enum.reduce_while(parameters, :ok, fn param, _acc ->
      value = Map.get(arguments, param.name)

      cond do
        is_nil(value) and param.required and param.name != "context" ->
          {:halt, {:error, {:missing_parameter, param.name}}}

        is_nil(value) ->
          {:cont, :ok}

        valid_type?(value, param.type) ->
          {:cont, :ok}

        true ->
          {:halt, {:error, {:invalid_type, param.name, param.type, value}}}
      end
    end)
  end

  defp valid_type?(value, "string"), do: is_binary(value)
  defp valid_type?(value, "integer"), do: is_integer(value)
  defp valid_type?(value, "number"), do: is_number(value)
  defp valid_type?(value, "float"), do: is_float(value)
  defp valid_type?(value, "boolean"), do: is_boolean(value)
  defp valid_type?(value, "array"), do: is_list(value)
  defp valid_type?(value, "object"), do: is_map(value)
  # Allow any type for unknown types
  defp valid_type?(_, _), do: true
end
