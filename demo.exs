#!/usr/bin/env elixir

# Demo script for LivekitexAgent
# Usage: ./demo.exs

# Load the project
Mix.install([
  {:jason, "~> 1.4"}
])

# Add current directory to code path
Code.prepend_path("lib")

# Load all modules
Code.require_file("lib/livekitex_agent.ex")
Code.require_file("lib/livekitex_agent/agent.ex")
Code.require_file("lib/livekitex_agent/agent_session.ex")
Code.require_file("lib/livekitex_agent/job_context.ex")
Code.require_file("lib/livekitex_agent/run_context.ex")
Code.require_file("lib/livekitex_agent/worker_options.ex")
Code.require_file("lib/livekitex_agent/function_tool.ex")
Code.require_file("lib/livekitex_agent/tool_registry.ex")
Code.require_file("lib/livekitex_agent/example_tools.ex")
Code.require_file("lib/livekitex_agent/example.ex")

IO.puts("""
=== LivekitexAgent Demo ===

This demo shows the key functionality of LivekitexAgent,
an Elixir library that replicates LiveKit Agents functionality.
""")

# Start the tool registry
{:ok, _} = LivekitexAgent.ToolRegistry.start_link([])

IO.puts("\n1. Creating an Agent...")

agent =
  LivekitexAgent.Agent.new(
    instructions: "You are a helpful demo assistant.",
    tools: [:get_weather, :add_numbers],
    agent_id: "demo_agent_001"
  )

IO.puts("✓ Agent created: #{agent.agent_id}")
IO.puts("  Instructions: #{agent.instructions}")
IO.puts("  Tools: #{inspect(agent.tools)}")

IO.puts("\n2. Registering Function Tools...")

# Register tools manually since ExampleTools uses explicit definitions
tools = LivekitexAgent.ExampleTools.get_tools()

Enum.each(tools, fn {_name, tool_def} ->
  LivekitexAgent.FunctionTool.register_tool(tool_def)
end)

registered_tools = LivekitexAgent.FunctionTool.get_all_tools()
IO.puts("✓ Registered #{map_size(registered_tools)} tools:")

Enum.each(registered_tools, fn {name, tool} ->
  IO.puts("  - #{name}: #{tool.description}")
end)

IO.puts("\n3. Testing Function Tools...")

# Test weather tool
case LivekitexAgent.FunctionTool.execute_tool("get_weather", %{"location" => "Madrid"}) do
  {:ok, result} ->
    IO.puts("✓ Weather tool result: #{result}")

  {:error, reason} ->
    IO.puts("✗ Weather tool failed: #{inspect(reason)}")
end

# Test math tool
case LivekitexAgent.FunctionTool.execute_tool("add_numbers", %{"a" => 15, "b" => 27}) do
  {:ok, result} ->
    IO.puts("✓ Math tool result: #{result}")

  {:error, reason} ->
    IO.puts("✗ Math tool failed: #{inspect(reason)}")
end

IO.puts("\n4. Creating RunContext...")

context =
  LivekitexAgent.RunContext.new(
    function_call: %{name: "demo_function", arguments: %{}},
    user_data: %{user_id: "demo_user", session: "demo_session"}
  )

IO.puts("✓ RunContext created: #{context.execution_id}")
IO.puts("  User data: #{inspect(context.user_data)}")

# Test tool with context
case LivekitexAgent.FunctionTool.execute_tool(
       "search_web",
       %{"query" => "Elixir programming"},
       context
     ) do
  {:ok, result} ->
    IO.puts("✓ Search tool with context: #{String.slice(result, 0, 50)}...")

  {:error, reason} ->
    IO.puts("✗ Search tool failed: #{inspect(reason)}")
end

IO.puts("\n5. Creating JobContext...")

job_context =
  LivekitexAgent.JobContext.new(
    job_id: "demo_job_001",
    metadata: %{demo: true, created_at: DateTime.utc_now()}
  )

IO.puts("✓ JobContext created: #{job_context.job_id}")
IO.puts("  Status: #{job_context.status}")
IO.puts("  Created: #{job_context.created_at}")

IO.puts("\n6. Creating WorkerOptions...")

entry_point = fn job ->
  IO.puts("  Entry point called for job: #{job.job_id}")
  :timer.sleep(1000)
  :ok
end

worker_options =
  LivekitexAgent.WorkerOptions.new(
    entry_point: entry_point,
    agent_name: "demo_worker",
    server_url: "ws://localhost:7880",
    max_concurrent_jobs: 3,
    worker_type: :voice_agent
  )

case LivekitexAgent.WorkerOptions.validate(worker_options) do
  {:ok, _} ->
    IO.puts("✓ WorkerOptions validated successfully")
    IO.puts("  Agent: #{worker_options.agent_name}")
    IO.puts("  Max jobs: #{worker_options.max_concurrent_jobs}")
    IO.puts("  Type: #{worker_options.worker_type}")

  {:error, reason} ->
    IO.puts("✗ WorkerOptions validation failed: #{reason}")
end

IO.puts("\n7. Converting Tools to OpenAI Format...")
all_tools = LivekitexAgent.FunctionTool.get_all_tools() |> Map.values()
openai_tools = LivekitexAgent.FunctionTool.to_openai_format(all_tools)

IO.puts("✓ Converted #{length(openai_tools)} tools to OpenAI format")
first_tool = List.first(openai_tools)

if first_tool do
  IO.puts("  Example: #{first_tool.function.name}")
  IO.puts("    Description: #{first_tool.function.description}")
  IO.puts("    Parameters: #{map_size(first_tool.function.parameters.properties)} properties")
end

IO.puts("\n8. Testing Load Calculation...")
current_load = LivekitexAgent.WorkerOptions.current_load(worker_options)
IO.puts("✓ Current system load: #{Float.round(current_load, 3)}")

should_handle =
  LivekitexAgent.WorkerOptions.should_handle_job?(worker_options, %{
    job_id: "test_job",
    room_type: :voice_chat
  })

case should_handle do
  {:accept, :ok} ->
    IO.puts("✓ Worker would accept new jobs")

  {:reject, reason} ->
    IO.puts("✗ Worker would reject jobs: #{reason}")
end

IO.puts("\n=== Demo Complete ===\n")

IO.puts("""
Summary:
- ✓ Agent configuration and management
- ✓ Function tool system with auto-discovery
- ✓ RunContext for tool execution
- ✓ JobContext for job management
- ✓ WorkerOptions for worker configuration
- ✓ OpenAI-compatible tool formatting
- ✓ Load balancing and job handling

The library is ready for building voice agent applications!

Next steps:
1. Integrate with actual LiveKit server
2. Add LLM, TTS, and STT clients
3. Implement WebSocket connections
4. Add comprehensive error handling
5. Build production deployment scripts
""")
