# Quick Start Guide: LivekitexAgent

## Installation

### Prerequisites

- Elixir ~> 1.12
- Erlang/OTP 24+
- LiveKit server (local or cloud)
- OpenAI API key (optional, for LLM/STT/TTS)

### Add to Project

Add to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:livekitex_agent, "~> 1.0"}
  ]
end
```

Install dependencies:

```bash
mix deps.get
```

## Basic Usage

### 1. Create Your First Agent

```elixir
# Create an agent with instructions and tools
agent = LivekitexAgent.Agent.new(
  instructions: "You are a helpful voice assistant. Be concise and friendly.",
  tools: [:get_weather, :add_numbers],
  agent_id: "my_first_agent"
)
```

### 2. Register Function Tools

```elixir
# Define custom tools using the macro
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
  def add_numbers(a, b) do
    a + b
  end
end

# Register the tools
LivekitexAgent.FunctionTool.register_module(MyTools)
```

### 3. Start an Agent Session

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
    end
  }
)

# Process text input
LivekitexAgent.AgentSession.process_text(session, "What's the weather like in Madrid?")
```

## Production Deployment

### 1. Create Worker Entry Point

Create `lib/my_app/agent_worker.ex`:

```elixir
defmodule MyApp.AgentWorker do
  @moduledoc """
  Production agent worker implementation.
  """

  def entry_point(job_context) do
    # Create agent for this job
    agent = LivekitexAgent.Agent.new(
      instructions: """
      You are a customer service assistant for MyApp.
      Help users with their questions and use available tools to provide information.
      """,
      tools: [:get_account_info, :process_payment, :book_appointment]
    )

    # Start session with job context
    {:ok, session} = LivekitexAgent.AgentSession.start_link(
      agent: agent,
      job_context: job_context,
      event_callbacks: %{
        error: fn _evt, data ->
          Logger.error("Session error: #{inspect(data)}")
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

### 2. Configure Worker Options

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

### 3. Start Worker Supervisor

```elixir
# In your application.ex
def start(_type, _args) do
  children = [
    # Your other supervisors...
    {LivekitexAgent.WorkerSupervisor, worker_options}
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### 4. CLI Deployment

Alternatively, use the CLI for deployment:

```bash
# Start production worker
livekitex_agent start \
  --agent-name my_app_agent \
  --server-url wss://your-livekit-server.com \
  --api-key $LIVEKIT_API_KEY \
  --api-secret $LIVEKIT_API_SECRET \
  --max-jobs 10

# Or use configuration file
livekitex_agent start --config config/prod.exs
```

## Development Workflow

### 1. Development Mode

```bash
# Start in development mode with hot reload
livekitex_agent dev \
  --agent-name dev_agent \
  --server-url ws://localhost:7880 \
  --hot-reload \
  --log-level debug
```

### 2. Testing Tools

```bash
# Test your function tools
livekitex_agent tools test get_weather --args '{"location": "New York"}'

# List all registered tools
livekitex_agent tools list

# Show tool schema
livekitex_agent tools schema get_weather --format json
```

### 3. Interactive Session

```bash
# Start interactive development session
livekitex_agent session --agent-name dev_agent --interactive
```

## Configuration Examples

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

### Provider Configuration

```elixir
# Configure different AI providers
config :livekitex_agent,
  providers: [
    # OpenAI for LLM and TTS
    openai: [
      api_key: System.get_env("OPENAI_API_KEY"),
      llm: [model: "gpt-4", temperature: 0.7],
      tts: [voice: "alloy", speed: 1.0]
    ],

    # Deepgram for STT
    deepgram: [
      api_key: System.get_env("DEEPGRAM_API_KEY"),
      model: "nova-2",
      language: "en-US"
    ],

    # ElevenLabs for premium TTS
    elevenlabs: [
      api_key: System.get_env("ELEVENLABS_API_KEY"),
      voice_id: "21m00Tcm4TlvDq8ikWAM"
    ]
  ]
```

## Phoenix Integration

### 1. Add to Phoenix Project

In your Phoenix application:

```elixir
# lib/my_app/agents/customer_service.ex
defmodule MyApp.Agents.CustomerService do
  @moduledoc """
  Customer service agent for Phoenix app integration.
  """

  def create_agent_for_user(user) do
    LivekitexAgent.Agent.new(
      instructions: """
      You are a customer service agent for #{user.company_name}.
      The user is #{user.name} (ID: #{user.id}).
      Help them with account questions and use tools to access their data.
      """,
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

  # ... other event handlers
end
```

### 2. LiveView Integration

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

    {:ok, assign(socket, call_id: call_id, agent_session: agent_session, messages: [])}
  end

  def handle_info({:text_received, text}, socket) do
    messages = socket.assigns.messages ++ [%{role: :user, text: text, timestamp: DateTime.utc_now()}]
    {:noreply, assign(socket, messages: messages)}
  end

  def handle_info({:response_generated, text}, socket) do
    messages = socket.assigns.messages ++ [%{role: :agent, text: text, timestamp: DateTime.utc_now()}]
    {:noreply, assign(socket, messages: messages)}
  end

  # Handle other events...
end
```

## Common Patterns

### Custom Tool with Context

```elixir
defmodule MyApp.Tools do
  use LivekitexAgent.FunctionTool

  @tool "Get user account information"
  @spec get_user_account(String.t()) :: String.t()
  def get_user_account(account_id, context \\ nil) do
    # Access session user data from context
    user_id = context && context.user_data[:user][:id]

    # Verify user can access this account
    if authorized?(user_id, account_id) do
      account = MyApp.Accounts.get_account(account_id)
      "Account balance: $#{account.balance}, Status: #{account.status}"
    else
      "Access denied: Cannot view this account information"
    end
  end

  defp authorized?(user_id, account_id) do
    # Your authorization logic
    MyApp.Accounts.user_can_access_account?(user_id, account_id)
  end
end
```

### Error Handling

```elixir
# Robust session handling with error recovery
defmodule MyApp.RobustSession do
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
    end
  end
end
```

## Next Steps

1. **Explore Examples**: Check out the `/examples` directory for more complete implementations
2. **Read Documentation**: Visit the full API documentation for advanced features
3. **Join Community**: Connect with other developers using LivekitexAgent
4. **Contribute**: Help improve the library by reporting issues or contributing code

## Troubleshooting

### Common Issues

**Connection Errors**:
```elixir
# Check LiveKit server connection
{:ok, session} = LivekitexAgent.AgentSession.start_link(agent: agent)
case LivekitexAgent.AgentSession.connect_to_room(session, room_url, token) do
  {:ok, :connected} -> IO.puts("Connected successfully")
  {:error, reason} -> IO.puts("Connection failed: #{inspect(reason)}")
end
```

**Tool Registration Issues**:
```bash
# Verify tools are registered
livekitex_agent tools list

# Test individual tools
livekitex_agent tools test my_tool --args '{"param": "value"}'
```

**Performance Issues**:
```elixir
# Monitor session metrics
metrics = LivekitexAgent.AgentSession.get_metrics(session)
IO.inspect(metrics, label: "Session Performance")
```

For more help, check the logs with increased verbosity:
```bash
livekitex_agent dev --log-level debug
```