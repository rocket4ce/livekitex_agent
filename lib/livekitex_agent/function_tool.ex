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

  defmacro __before_compile__(env) do
    tools = Module.get_attribute(env.module, :tools) || []

    quote do
      def __tools__ do
        unquote(Macro.escape(build_tool_definitions(env.module, tools)))
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
  Registers a module's tools in the global tool registry.
  """
  def register_module(module) do
    if function_exported?(module, :__tools__, 0) do
      tools = module.__tools__()
      Enum.each(tools, &register_tool/1)
    else
      raise "Module #{module} does not define any tools. Use `use LivekitexAgent.FunctionTool` and @tool attributes."
    end
  end

  @doc """
  Registers a single tool in the global registry.
  """
  def register_tool(tool_definition) do
    LivekitexAgent.ToolRegistry.register(tool_definition)
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
  """
  def execute_tool(tool_name, arguments, context \\ nil) do
    case get_tool(tool_name) do
      nil ->
        {:error, :tool_not_found}

      tool ->
        execute_tool_definition(tool, arguments, context)
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

  defp build_tool_definitions(module, descriptions) do
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

  defp execute_tool_definition(tool, arguments, context) do
    case validate_arguments(tool, arguments) do
      :ok ->
        do_execute_tool(tool, arguments, context)

      {:error, reason} ->
        {:error, reason}
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

    # Build argument list
    args =
      Enum.map(sorted_params, fn param ->
        case param.name do
          "context" -> context
          name -> Map.get(arguments, name)
        end
      end)

    # Filter out nil context if function doesn't expect it
    if context == nil and has_context_parameter?(tool) do
      List.delete_at(args, -1)
    else
      args
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
            name: "param_#{index}",
            type: format_type(type),
            position: index,
            required: true
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

  defp build_openai_properties(parameters) do
    parameters
    |> Enum.reject(&(&1.name == "context"))
    |> Enum.reduce(%{}, fn param, acc ->
      Map.put(acc, param.name, %{
        type: openai_type(param.type),
        description: param[:description] || "Parameter #{param.name}"
      })
    end)
  end

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

  defp validate_parameter_types(parameters, arguments) do
    # Basic type validation - would be more comprehensive in production
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
          {:halt, {:error, {:invalid_type, param.name, param.type}}}
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
