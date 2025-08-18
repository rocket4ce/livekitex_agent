defmodule LivekitexAgent.FunctionToolTest do
  use ExUnit.Case

  # Mock tool module for testing
  defmodule TestTools do
    @doc """
    Add two numbers together.
    """
    @spec add(number(), number()) :: number()
    def add(a, b) do
      a + b
    end

    @doc """
    Get a greeting message.
    """
    @spec greet(String.t()) :: String.t()
    def greet(name) do
      "Hello, #{name}!"
    end

    @doc """
    Tool with context.
    """
    @spec tool_with_context(String.t(), LivekitexAgent.RunContext.t()) :: String.t()
    def tool_with_context(message, _context) do
      "Processed: #{message}"
    end

    @doc """
    Returns tools definition for this module.
    """
    def get_tools do
      %{
        "add" => %{
          name: "add",
          description: "Add two numbers together",
          module: __MODULE__,
          function: :add,
          arity: 2,
          parameters: [
            %{name: "a", type: "number", required: true, position: 0},
            %{name: "b", type: "number", required: true, position: 1}
          ]
        },
        "greet" => %{
          name: "greet",
          description: "Get a greeting message",
          module: __MODULE__,
          function: :greet,
          arity: 1,
          parameters: [%{name: "name", type: "string", required: true, position: 0}]
        },
        "tool_with_context" => %{
          name: "tool_with_context",
          description: "Tool with context",
          module: __MODULE__,
          function: :tool_with_context,
          arity: 2,
          parameters: [
            %{name: "message", type: "string", required: true, position: 0}
          ]
        }
      }
    end
  end

  describe "FunctionTool" do
    test "tool execution works" do
      # ToolRegistry is already started by the application
      # Just ensure it's registered
      case GenServer.whereis(LivekitexAgent.ToolRegistry) do
        nil ->
          # Start if not started
          {:ok, _pid} = LivekitexAgent.ToolRegistry.start_link([])

        _pid ->
          # Already started, continue
          :ok
      end

      # Register test tools
      tools = LivekitexAgent.ExampleTools.get_tools()

      Enum.each(tools, fn {_name, tool_def} ->
        LivekitexAgent.ToolRegistry.register(tool_def)
      end)

      # Execute a tool
      {:ok, result} =
        LivekitexAgent.FunctionTool.execute_tool("add_numbers", %{"a" => 5, "b" => 3})

      assert result == 8

      {:ok, result} =
        LivekitexAgent.FunctionTool.execute_tool("to_uppercase", %{"text" => "hello"})

      assert result == "HELLO"
    end

    test "converts to OpenAI format" do
      tools = TestTools.get_tools() |> Map.values()
      openai_format = LivekitexAgent.FunctionTool.to_openai_format(tools)

      assert is_list(openai_format)
      assert length(openai_format) == 3

      add_tool = Enum.find(openai_format, &(&1.function.name == "add"))
      assert add_tool.type == "function"
      assert add_tool.function.description == "Add two numbers together"
    end

    test "validates arguments correctly" do
      add_tool = %{
        parameters: [
          %{name: "a", type: "number", required: true, position: 0},
          %{name: "b", type: "number", required: true, position: 1}
        ]
      }

      # Valid arguments
      assert :ok = LivekitexAgent.FunctionTool.validate_arguments(add_tool, %{"a" => 1, "b" => 2})

      # Missing required parameter
      assert {:error, {:missing_parameters, ["b"]}} =
               LivekitexAgent.FunctionTool.validate_arguments(add_tool, %{"a" => 1})
    end
  end
end
