# LivekitexAgent Quick Start Guide

This guide will help you get up and running with LivekitexAgent quickly. Whether you're building a simple voice assistant or a complex production system, this guide covers everything you need to know.

## Prerequisites

Before you start, make sure you have:

- **Elixir**: ~> 1.12
- **Erlang/OTP**: 24+
- **LiveKit server**: Local or cloud instance
- **OpenAI API key**: Optional, for AI features

## Installation

### Add to Your Project

Add `livekitex_agent` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:livekitex_agent, "~> 1.0.0"}
  ]
end
```

Then install dependencies:

```bash
mix deps.get
```

## Getting Started in 5 Minutes

### Step 1: Create Your First Agent

```elixir
# Create an agent with instructions and capabilities
agent = LivekitexAgent.Agent.new(
  instructions: "You are a helpful voice assistant. Be concise and friendly.",
  tools: [:get_weather, :add_numbers],
  agent_id: "my_first_agent"
)
```

### Step 2: Define Function Tools

Create powerful tools your agent can use:

```elixir
defmodule MyTools do
  use LivekitexAgent.FunctionTool

  @tool "Get weather information for a location"
  @spec get_weather(String.t()) :: String.t()
  def get_weather(location) do
    # Your weather API integration here
    "Weather in #{location}: Sunny, 25°C"
  end

  @tool "Calculate the sum of two numbers"
  @spec add_numbers(number(), number()) :: number()
  def add_numbers(a, b) when is_number(a) and is_number(b) do
    a + b
  end

  @tool "Search with execution context"
  @spec search_database(String.t(), LivekitexAgent.RunContext.t()) :: String.t()
  def search_database(query, context) do
    LivekitexAgent.RunContext.log_info(context, "Searching for: #{query}")
    # Your search implementation
    "Search results for #{query}"
  end
end

# Register all tools from the module
LivekitexAgent.FunctionTool.register_module(MyTools)
```

### Step 3: Start an Agent Session

```elixir
# Start a session with event callbacks
{:ok, session} = LivekitexAgent.AgentSession.start_link(
  agent: agent,
  event_callbacks: %{
    session_started: fn _evt, data ->
      IO.puts("Session started: #{data.session_id}")
    end,
    text_received: fn _evt, data ->
      IO.puts("User said: #{data.text}")
    end,
    response_generated: fn _evt, data ->
      IO.puts("Agent replied: #{data.text}")
    end,
    tool_call_completed: fn _evt, data ->
      IO.puts("Tool executed: #{data.tool_name} -> #{data.result}")
    end
  }
)

# Process text input
LivekitexAgent.AgentSession.process_text(session, "What's the weather like in Madrid?")
```

### Step 4: Add Real-time Voice

Enable voice conversations with OpenAI's Realtime API:

```bash
export OPENAI_API_KEY="your-openai-key"
```

```elixir
# Configure realtime settings
realtime_config = %{
  url: System.get_env("OAI_REALTIME_URL") ||
       "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17",
  api_key: System.get_env("OPENAI_API_KEY"),
  log_frames: true
}

# Start session with voice capabilities
{:ok, session} = LivekitexAgent.AgentSession.start_link(
  agent: agent,
  realtime_config: realtime_config
)

# Stream audio (PCM16 mono 16kHz)
LivekitexAgent.AgentSession.stream_audio(session, pcm16_audio_chunk)
LivekitexAgent.AgentSession.commit_audio(session)
```

## Running the Examples

Try the built-in examples to see LivekitexAgent in action:

```bash
# Basic realtime assistant
export OPENAI_API_KEY="your-key"
mix run examples/minimal_realtime_assistant.exs

# Weather agent with tools
mix run examples/weather_agent.exs

# Joke teller with real-time processing
mix run examples/realtime_joke_teller.exs
```

## Production Deployment

### Create a Worker Entry Point

Create `lib/my_app/agent_worker.ex`:

```elixir
defmodule MyApp.AgentWorker do
  @moduledoc """
  Production agent worker implementation.
  """

  def entry_point(job_context) do
    # Create agent for this job
    agent = LivekitexAgent.Agent.new(
      instructions: \"\"\"
      You are a customer service assistant for MyApp.
      Help users with their questions and use available tools to provide information.
      \"\"\",
      tools: [:get_account_info, :process_payment, :book_appointment]
    )

    # Start session with job context
    {:ok, session} = LivekitexAgent.AgentSession.start_link(
      agent: agent,
      job_context: job_context,
      event_callbacks: %{
        error: fn _evt, data ->
          Logger.error("Session error: #{inspect(data)}")
        end,
        session_ended: fn _evt, data ->
          Logger.info("Session completed: #{inspect(data)}")
        end
      }
    )

    # Connect to LiveKit room
    LivekitexAgent.AgentSession.connect_to_room(
      session,
      job_context.room_url,
      job_context.access_token
    )

    # Keep session alive
    Process.monitor(session)
    receive do
      {:DOWN, _ref, :process, ^session, reason} ->
        Logger.info("Session ended: #{inspect(reason)}")
    end
  end
end
```

### Configure Worker Options

```elixir
# Create worker configuration
worker_options = LivekitexAgent.WorkerOptions.new(
  entry_point: &MyApp.AgentWorker.entry_point/1,
  agent_name: "my_app_agent",
  server_url: "wss://your-livekit-server.com",
  api_key: System.get_env("LIVEKIT_API_KEY"),
  api_secret: System.get_env("LIVEKIT_API_SECRET"),
  max_concurrent_jobs: 10,
  worker_type: :voice_agent
)
```

### Start Worker Supervisor

Add to your `application.ex`:

```elixir
def start(_type, _args) do
  children = [
    # Your other supervisors...
    {LivekitexAgent.ToolRegistry, []},
    {LivekitexAgent.WorkerSupervisor, worker_options}
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### CLI Deployment

Use the CLI for quick deployment:

```bash
# Start production worker
mix run -e "LivekitexAgent.CLI.main([
  'start',
  '--agent-name', 'my_app_agent',
  '--server-url', 'wss://your-livekit-server.com',
  '--api-key', \$LIVEKIT_API_KEY,
  '--api-secret', \$LIVEKIT_API_SECRET,
  '--max-jobs', '10'
])"

# Check health
mix run -e "LivekitexAgent.CLI.main(['health'])"
```

## Development Workflow

### Development Mode

```bash
# Start in development mode with hot reload
mix run -e "LivekitexAgent.CLI.main([
  'dev',
  '--agent-name', 'dev_agent',
  '--server-url', 'ws://localhost:7880',
  '--hot-reload',
  '--log-level', 'debug'
])"
```

### Testing Tools

```bash
# Test function tools interactively
iex -S mix

# In IEx:
iex> LivekitexAgent.FunctionTool.execute_tool("get_weather", %{"location" => "Madrid"})
{:ok, "Weather in Madrid: Sunny, 25°C"}

# List all registered tools
iex> LivekitexAgent.FunctionTool.get_all_tools() |> Map.keys()
[:get_weather, :add_numbers, :search_database]
```

## Configuration

### Basic Configuration

```elixir
# config/config.exs
import Config

config :livekitex_agent,
  # Default worker settings
  agent_name: "default_agent",
  server_url: "ws://localhost:7880",
  max_concurrent_jobs: 5,

  # Logging
  log_level: :info,

  # Health check
  health_check_port: 8080
```

### Production Configuration

```elixir
# config/prod.exs
import Config

config :livekitex_agent,
  agent_name: System.get_env("AGENT_NAME", "production_agent"),
  server_url: System.get_env("LIVEKIT_SERVER_URL"),
  api_key: System.get_env("LIVEKIT_API_KEY"),
  api_secret: System.get_env("LIVEKIT_API_SECRET"),
  max_concurrent_jobs: String.to_integer(System.get_env("MAX_JOBS", "20")),
  worker_type: :voice_agent,
  region: System.get_env("REGION", "us-west-2"),

  # Health and monitoring
  health_check_port: 8080,
  drain_timeout: 30_000,

  # Logging
  log_level: :info,
  structured_logging: true,

  # AI Providers
  openai: [
    api_key: System.get_env("OPENAI_API_KEY"),
    model: "gpt-4",
    temperature: 0.7
  ],

  # Audio settings
  audio: [
    sample_rate: 16000,
    channels: 1,
    format: :pcm16,
    vad_sensitivity: 0.6
  ]
```

### Environment Variables

```bash
# Required for LiveKit connection
export LIVEKIT_API_KEY="your-livekit-api-key"
export LIVEKIT_API_SECRET="your-livekit-api-secret"

# Required for OpenAI features
export OPENAI_API_KEY="your-openai-key"

# Optional customization
export AGENT_NAME="my_production_agent"
export MAX_JOBS="20"
export LOG_LEVEL="info"
```

## Phoenix Integration

### Add to Phoenix Application

```elixir
# lib/my_app/agents/customer_service.ex
defmodule MyApp.Agents.CustomerService do
  @moduledoc \"\"\"
  Customer service agent for Phoenix app integration.
  \"\"\"

  def create_agent_for_user(user) do
    LivekitexAgent.Agent.new(
      instructions: \"\"\"
      You are a customer service agent for #{user.company_name}.
      The user is #{user.name} (ID: #{user.id}).
      Help them with account questions and use tools to access their data.
      \"\"\",
      tools: [:get_user_account, :update_preferences, :create_support_ticket],
      agent_id: "customer_service_#{user.id}",
      metadata: %{user_id: user.id, company_id: user.company_id}
    )
  end

  def start_session_for_call(user, call_id) do
    agent = create_agent_for_user(user)

    {:ok, session} = LivekitexAgent.AgentSession.start_link(
      agent: agent,
      user_data: %{user: user, call_id: call_id},
      event_callbacks: %{
        session_started: &handle_session_started/2,
        text_received: &handle_text_received/2,
        tool_call_completed: &handle_tool_completed/2
      }
    )

    # Register session for this call
    Registry.register(MyApp.CallRegistry, call_id, session)
    {:ok, session}
  end

  defp handle_session_started(_event, data) do
    # Log to Phoenix or update UI via PubSub
    Phoenix.PubSub.broadcast(MyApp.PubSub, "calls:#{data.call_id}",
      {:session_started, data.session_id})
  end

  # ... implement other event handlers
end
```

### LiveView Integration

```elixir
# lib/my_app_web/live/call_live.ex
defmodule MyAppWeb.CallLive do
  use MyAppWeb, :live_view

  def mount(%{"call_id" => call_id}, _session, socket) do
    user = get_current_user(socket)

    # Start agent session for this call
    {:ok, agent_session} = MyApp.Agents.CustomerService.start_session_for_call(user, call_id)

    # Subscribe to session events
    Phoenix.PubSub.subscribe(MyApp.PubSub, "calls:#{call_id}")

    {:ok, assign(socket,
      call_id: call_id,
      agent_session: agent_session,
      messages: []
    )}
  end

  def handle_event("send_message", %{"message" => text}, socket) do
    LivekitexAgent.AgentSession.process_text(socket.assigns.agent_session, text)
    messages = socket.assigns.messages ++ [%{role: :user, text: text, timestamp: DateTime.utc_now()}]
    {:noreply, assign(socket, messages: messages)}
  end

  def handle_info({:text_received, text}, socket) do
    messages = socket.assigns.messages ++ [%{role: :user, text: text, timestamp: DateTime.utc_now()}]
    {:noreply, assign(socket, messages: messages)}
  end

  def handle_info({:response_generated, text}, socket) do
    messages = socket.assigns.messages ++ [%{role: :agent, text: text, timestamp: DateTime.utc_now()}]
    {:noreply, assign(socket, messages: messages)}
  end
end
```

## Common Patterns

### Custom Tool with Context Access

```elixir
defmodule MyApp.Tools do
  use LivekitexAgent.FunctionTool

  @tool "Get user account information"
  @spec get_user_account(String.t(), LivekitexAgent.RunContext.t()) :: String.t()
  def get_user_account(account_id, context) do
    # Access session user data from context
    user_id = context.user_data[:user][:id]

    # Verify user can access this account
    if authorized?(user_id, account_id) do
      account = MyApp.Accounts.get_account(account_id)
      "Account balance: $#{account.balance}, Status: #{account.status}"
    else
      "Access denied: Cannot view this account information"
    end
  end

  @tool "Create support ticket with user context"
  @spec create_support_ticket(String.t(), String.t(), LivekitexAgent.RunContext.t()) :: String.t()
  def create_support_ticket(subject, description, context) do
    user = context.user_data[:user]

    case MyApp.Support.create_ticket(%{
      user_id: user.id,
      subject: subject,
      description: description,
      priority: "normal"
    }) do
      {:ok, ticket} ->
        "Support ticket ##{ticket.id} created successfully"
      {:error, reason} ->
        "Failed to create ticket: #{reason}"
    end
  end

  defp authorized?(user_id, account_id) do
    # Your authorization logic
    MyApp.Accounts.user_can_access_account?(user_id, account_id)
  end
end
```

### Error Handling and Recovery

```elixir
defmodule MyApp.RobustSession do
  require Logger

  def start_monitored_session(agent, opts \\ []) do
    case LivekitexAgent.AgentSession.start_link([agent: agent] ++ opts) do
      {:ok, pid} ->
        Process.monitor(pid)
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start session: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def handle_session_down(pid, reason) do
    Logger.warn("Session #{inspect(pid)} crashed: #{inspect(reason)}")

    case reason do
      :normal -> :ok
      :shutdown -> :ok
      {:shutdown, _} -> :ok
      _ ->
        # Restart session or alert monitoring
        send_alert("Session crashed unexpectedly", %{pid: pid, reason: reason})
        # Optionally restart
        restart_session_if_needed(pid, reason)
    end
  end

  defp restart_session_if_needed(pid, reason) do
    # Implement your restart logic based on crash reason
    Logger.info("Considering restart for session #{inspect(pid)}")
  end

  defp send_alert(message, metadata) do
    # Send to your monitoring system
    Logger.error("ALERT: #{message} - #{inspect(metadata)}")
  end
end
```

### Performance Monitoring

```elixir
defmodule MyApp.SessionMonitor do
  def monitor_session_performance(session_pid) do
    # Get session metrics
    metrics = LivekitexAgent.AgentSession.get_metrics(session_pid)

    # Log performance data
    Logger.info("Session performance", [
      session_id: metrics.session_id,
      uptime: metrics.uptime_ms,
      messages_processed: metrics.messages_count,
      tools_executed: metrics.tools_count,
      avg_response_time: metrics.avg_response_time_ms
    ])

    # Check for performance issues
    if metrics.avg_response_time_ms > 5000 do
      Logger.warn("Slow session detected", session_id: metrics.session_id)
    end

    metrics
  end
end
```

## Troubleshooting

### Common Issues and Solutions

#### Connection Problems

```elixir
# Test LiveKit server connection
def test_connection(server_url, api_key, api_secret) do
  case LivekitexAgent.Realtime.ConnectionManager.test_connection(
    server_url, api_key, api_secret
  ) do
    {:ok, :connected} ->
      IO.puts("✅ Connection successful")
    {:error, :timeout} ->
      IO.puts("❌ Connection timeout - check server URL")
    {:error, :unauthorized} ->
      IO.puts("❌ Authorization failed - check API key/secret")
    {:error, reason} ->
      IO.puts("❌ Connection failed: #{inspect(reason)}")
  end
end
```

#### Tool Registration Issues

```elixir
# Verify tools are properly registered
def check_tool_registration do
  tools = LivekitexAgent.FunctionTool.get_all_tools()

  IO.puts("Registered tools:")
  for {name, tool} <- tools do
    IO.puts("  - #{name}: #{tool.description}")
  end

  # Test tool execution
  case LivekitexAgent.FunctionTool.execute_tool("get_weather", %{"location" => "Test"}) do
    {:ok, result} -> IO.puts("✅ Tool execution successful: #{result}")
    {:error, reason} -> IO.puts("❌ Tool execution failed: #{inspect(reason)}")
  end
end
```

#### Audio Format Issues

```elixir
# Validate audio format
def validate_audio_format(audio_data) do
  case LivekitexAgent.Media.AudioProcessor.validate_format(audio_data) do
    {:ok, info} ->
      IO.puts("✅ Audio format valid: #{inspect(info)}")
    {:error, :invalid_format} ->
      IO.puts("❌ Audio must be PCM16 mono 16kHz")
    {:error, reason} ->
      IO.puts("❌ Audio validation failed: #{inspect(reason)}")
  end
end
```

### Debug Mode

Enable debug logging for troubleshooting:

```elixir
# Enable debug logging in development
Logger.configure(level: :debug)

# Or use CLI debug mode
mix run -e "LivekitexAgent.CLI.main(['dev', '--log-level', 'debug'])"
```

### Performance Tuning

```elixir
# Monitor memory usage
def check_memory_usage do
  :erlang.memory() |> Enum.each(fn {type, bytes} ->
    mb = Float.round(bytes / (1024 * 1024), 2)
    IO.puts("#{type}: #{mb} MB")
  end)
end

# Monitor process count
def check_process_count do
  count = :erlang.system_info(:process_count)
  limit = :erlang.system_info(:process_limit)
  IO.puts("Processes: #{count}/#{limit}")
end
```

## Next Steps

1. **Explore Advanced Features**: Check out the main documentation for advanced features like custom providers, multi-modal processing, and enterprise deployment patterns.

2. **Study the Examples**: Look at the complete examples in the `/examples` directory to understand real-world usage patterns.

3. **Join the Community**: Connect with other developers, ask questions, and share your implementations.

4. **Performance Optimization**: Learn about optimizing your agents for production workloads.

5. **Custom Providers**: Implement your own STT/TTS/VAD providers for specialized requirements.

## Getting Help

- **API Documentation**: Run `mix docs` and open `doc/index.html`
- **GitHub Issues**: Report bugs or request features
- **Community Discussions**: Ask questions and share experiences
- **Examples**: Study the working examples in `/examples/`

Happy building with LivekitexAgent! 🚀