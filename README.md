# LivekitexAgent

[![Elixir](https://img.shields.io/badge/elixir-%3E%3D1.12-blue)](https://elixir-lang.org/)
[![OTP](https://img.shields.io/badge/OTP-%3E%3D24-blue)](https://www.erlang.org/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A complete Elixir implementation of LiveKit Agents for building real-time conversational AI applications. LivekitexAgent provides a robust, fault-tolerant framework for creating voice agents with natural language processing, speech recognition, text-to-speech, and custom function tools.

## 🚀 Features

### Core Agent System
- **Agent Configuration**: Instructions, tools, and AI component integration
- **Session Management**: Conversation state, turn handling, and event callbacks
- **Real-time Audio**: Sub-100ms latency audio processing with PCM16 support
- **Function Tools**: Macro-based tool definitions with automatic OpenAI schema generation

### AI Provider Integration
- **OpenAI Integration**: Complete LLM, STT, TTS, and Realtime API support
- **Pluggable Architecture**: Custom provider implementations via behaviours
- **Multi-modal Support**: Audio, video, and text processing capabilities

### Production Ready
- **Worker Management**: Load balancing, job distribution, and health monitoring
- **Fault Tolerance**: OTP supervision trees and circuit breaker patterns
- **Scalability**: Handle 100+ concurrent sessions with automatic scaling
- **Monitoring**: Comprehensive metrics, logging, and health endpoints

### Developer Experience
- **CLI Tools**: Development and production deployment commands
- **Phoenix Integration**: LiveView helpers and PubSub integration
- **Examples**: Complete working examples for common use cases
- **Hot Reload**: Development mode with automatic code reloading

## 📋 Requirements

- **Elixir**: ~> 1.12
- **Erlang/OTP**: 24+
- **LiveKit Server**: Local or cloud instance
- **Optional**: OpenAI API key for AI features

## 📦 Installation

Add `livekitex_agent` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:livekitex_agent, "~> 0.1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## 🚀 Quick Start

### 1. Create Your First Agent

```elixir
# Define your agent with instructions and capabilities
agent = LivekitexAgent.Agent.new(
  instructions: "You are a helpful voice assistant. Be concise and friendly.",
  tools: [:get_weather, :add_numbers],
  agent_id: "my_voice_agent"
)
```

### 2. Start a Session

```elixir
# Start an agent session with event callbacks
{:ok, session} = LivekitexAgent.AgentSession.start_link(
  agent: agent,
  event_callbacks: %{
    session_started: fn _evt, data ->
      IO.inspect(data, label: "session_started")
    end,
    text_received: fn _evt, data ->
      IO.inspect(data, label: "text_received")
    end,
    response_complete: fn _evt, data ->
      IO.inspect(data, label: "response_complete")
    end
  }
)

# Send text and get a response
LivekitexAgent.AgentSession.process_text(session, "What's the weather like in Madrid?")
```

### 3. Define Custom Function Tools

Create powerful function tools that your agent can call:

```elixir
defmodule MyTools do
  use LivekitexAgent.FunctionTool

  @tool "Get weather information for a location"
  @spec get_weather(String.t()) :: String.t()
  def get_weather(location) do
    # Your weather API integration here
    "Weather in #{location}: Sunny, 25°C"
  end

  @tool "Search with context access"
  @spec search_web(String.t(), LivekitexAgent.RunContext.t()) :: String.t()
  def search_web(query, context) do
    LivekitexAgent.RunContext.log_info(context, "Searching: #{query}")
    # Your search implementation here
    "Search results for #{query}"
  end

  @tool "Add numbers with validation"
  @spec add_numbers(number(), number()) :: number()
  def add_numbers(a, b) when is_number(a) and is_number(b) do
    a + b
  end
end

# Register all tools from the module
LivekitexAgent.FunctionTool.register_module(MyTools)

# Tools are automatically converted to OpenAI function schemas
openai_tools = LivekitexAgent.FunctionTool.get_all_tools()
               |> Map.values()
               |> LivekitexAgent.FunctionTool.to_openai_format()
```

### 4. Real-time Voice Conversations

Enable real-time voice interactions with OpenAI's Realtime API:

```elixir
# Configure environment variables
# OPENAI_API_KEY or OAI_API_KEY
# OAI_REALTIME_URL (optional)

# Configure realtime settings
realtime_config = %{
  url: System.get_env("OAI_REALTIME_URL") ||
       "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17",
  api_key: System.get_env("OPENAI_API_KEY"),
  log_frames: true  # Enable debugging
}

# Start session with realtime capabilities
{:ok, session} = LivekitexAgent.AgentSession.start_link(
  agent: agent,
  realtime_config: realtime_config
)

# Send text message
LivekitexAgent.AgentSession.send_text(session, "Hello, how are you?")

# Stream audio (PCM16 mono 16kHz)
LivekitexAgent.AgentSession.stream_audio(session, pcm16_chunk)
LivekitexAgent.AgentSession.commit_audio(session)

# Cancel ongoing response
LivekitexAgent.AgentSession.cancel_response(session)
```

## 🔧 Advanced Features

### Voice Processing Pipeline

LivekitexAgent supports pluggable voice components through behaviours:

- **VAD (Voice Activity Detection)**: `LivekitexAgent.VADClient`
- **STT (Speech-to-Text)**: `LivekitexAgent.STTClient`
- **TTS (Text-to-Speech)**: `LivekitexAgent.TTSClient`

Configure components when creating your agent:

#### Built-in Energy-Based VAD

```elixir
agent = LivekitexAgent.Agent.new(
  instructions: "You are a helpful voice assistant.",
  vad_config: %{
    module: LivekitexAgent.SimpleEnergyVAD,
    opts: [sample_rate: 16_000]
  }
)

{:ok, session} = LivekitexAgent.AgentSession.start_link(agent: agent)

# Stream audio - VAD automatically detects speech boundaries
LivekitexAgent.AgentSession.stream_audio(session, pcm16_chunk)
```

#### Custom STT Implementation

```elixir
defmodule MyCustomSTT do
  use GenServer
  @behaviour LivekitexAgent.STTClient

  def start_link(parent: parent, opts: opts) do
    GenServer.start_link(__MODULE__, {parent, opts})
  end

  def init({parent, opts}) do
    {:ok, %{parent: parent, opts: opts}}
  end

  def handle_info({:process_utterance, pcm16}, state) do
    # Integrate with your preferred STT service
    text = transcribe_with_provider(pcm16, state.opts)
    send(state.parent, {:stt_result, text})
    {:noreply, state}
  end

  defp transcribe_with_provider(audio_data, opts) do
    # Your STT implementation here
    "Transcribed text from audio"
  end
end

# Use your custom STT
agent = LivekitexAgent.Agent.new(
  instructions: "You are a helpful assistant.",
  stt_config: %{module: MyCustomSTT, opts: [language: "en"]},
  vad_config: %{module: LivekitexAgent.SimpleEnergyVAD, opts: []}
)
```

#### Custom TTS Implementation

```elixir
defmodule MyCustomTTS do
  use GenServer
  @behaviour LivekitexAgent.TTSClient

  def start_link(parent: parent, opts: opts) do
    GenServer.start_link(__MODULE__, {parent, opts})
  end

  def init({parent, opts}) do
    {:ok, %{parent: parent, opts: opts}}
  end

  def handle_info({:synthesize, text}, state) do
    # Integrate with your preferred TTS service
    pcm16_audio = synthesize_with_provider(text, state.opts)
    send(state.parent, {:tts_complete, pcm16_audio})
    {:noreply, state}
  end

  defp synthesize_with_provider(text, opts) do
    # Your TTS implementation here
    <<0::binary-size(1600)>>  # Placeholder PCM16 data
  end
end

# Use your custom TTS
agent = LivekitexAgent.Agent.new(
  instructions: "You are a helpful assistant.",
  tts_config: %{module: MyCustomTTS, opts: [voice: "alloy", language: "en"]}
)
```

### Realtime + VAD Integration

Combine real-time processing with automatic voice activity detection:

```elixir
agent = LivekitexAgent.Agent.new(
  instructions: "You are a helpful voice assistant.",
  vad_config: %{module: LivekitexAgent.SimpleEnergyVAD, opts: []}
)

realtime_config = %{
  url: System.get_env("OAI_REALTIME_URL") ||
       "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17",
  api_key: System.get_env("OPENAI_API_KEY"),
  log_frames: true
}

{:ok, session} = LivekitexAgent.AgentSession.start_link(
  agent: agent,
  realtime_config: realtime_config
)

# VAD automatically commits audio when speech ends
LivekitexAgent.AgentSession.stream_audio(session, pcm16_chunk)
```

> **Audio Requirements**: PCM16 mono 16kHz. Convert your audio source if needed.

## 📖 Examples

### Built-in Examples

Run these complete examples to see LivekitexAgent in action:

#### Minimal Realtime Assistant
```bash
export OPENAI_API_KEY="your-key-here"
mix run examples/minimal_realtime_assistant.exs
```

#### Weather Agent with Tools
```bash
export OPENAI_API_KEY="your-key-here"
mix run examples/weather_agent.exs
```

#### Joke Teller (Real-time)
```bash
export OPENAI_API_KEY="your-key-here"
mix run examples/realtime_joke_teller.exs
```

### Customization Tips

- Use `event_callbacks` in `AgentSession` to log conversation deltas or publish metrics
- Implement custom STT/TTS/VAD providers for specialized use cases
- Create domain-specific tools for your business logic

## 🏭 Production Deployment

### Worker Management

Set up supervised workers for production deployments:

```elixir
# Define your entry point function
entry_point = fn job ->
  agent = LivekitexAgent.Agent.new(
    instructions: "You are a helpful production assistant.",
    tools: [:get_weather, :search_database]
  )

  {:ok, session} = LivekitexAgent.AgentSession.start_link(agent: agent)

  # Monitor the session
  Process.monitor(session)
  receive do
    {:DOWN, _ref, :process, ^session, _reason} -> :ok
  end
end

# Configure worker options
worker_options = LivekitexAgent.WorkerOptions.new(
  entry_point: entry_point,
  agent_name: "production_agent",
  server_url: "wss://your-livekit-server.com",
  api_key: "your-api-key",
  api_secret: "your-api-secret",
  max_concurrent_jobs: 10
)

# Start the worker supervisor
{:ok, supervisor_pid} = LivekitexAgent.WorkerSupervisor.start_link(worker_options)

# Assign jobs programmatically
{:ok, job_id} = LivekitexAgent.WorkerManager.assign_job(%{
  room: %{name: "customer_call_1"},
  participant: %{identity: "caller_123"}
})
```

### Job and Run Contexts

#### JobContext - Manage Job Lifecycle

```elixir
# Start a job context
{:ok, job} = LivekitexAgent.JobContext.start_link(job_id: "customer_call_123")

# Add participants
LivekitexAgent.JobContext.add_participant(job, "user_1", %{
  name: "Alice",
  phone: "+1234567890"
})

# Start background tasks
LivekitexAgent.JobContext.start_task(job, "transcription", fn ->
  # Your background processing
  :timer.sleep(1000)
  {:ok, "transcription_complete"}
end)

# Get job information
info = LivekitexAgent.JobContext.get_info(job)

# Clean shutdown
LivekitexAgent.JobContext.shutdown(job)
```

#### RunContext - Tool Execution Context

```elixir
# Create context for tool execution
run_context = LivekitexAgent.RunContext.new(
  session: session_pid,
  function_call: %{
    name: "get_weather",
    arguments: %{"location" => "Madrid", "units" => "metric"}
  }
)

# Log information during tool execution
LivekitexAgent.RunContext.log_info(run_context, "Fetching weather data...")
LivekitexAgent.RunContext.log_error(run_context, "API rate limit exceeded")
```

## 🛠️ CLI Usage

### Development Mode

```bash
# Start with hot reload and debug logging
mix run -e "LivekitexAgent.CLI.main(['dev', '--hot-reload', '--log-level', 'debug'])"
```

### Production Mode

```bash
# Start production agent
mix run -e "LivekitexAgent.CLI.main([
  'start',
  '--agent-name', 'production_agent',
  '--production',
  '--server-url', 'wss://your-livekit-server.com'
])"
```

### Health Checks

```bash
# Check system health
mix run -e "LivekitexAgent.CLI.main(['health'])"
```

### Configuration Files

Create a JSON configuration file for easier deployment:

```json
{
  "agent_name": "production_agent",
  "server_url": "wss://prod.livekit.cloud",
  "api_key": "your-production-key",
  "api_secret": "your-production-secret",
  "max_jobs": 10,
  "log_level": "info",
  "timeout": 300000
}
```

Use the configuration file:

```bash
mix run -e "LivekitexAgent.CLI.main(['start', '--config-file', './config/production.json'])"
```

## 🔧 Development

### Setup

```bash
# Get dependencies
mix deps.get

# Compile the project
mix compile

# Run tests
mix test

# Run tests with coverage
mix test --cover
```

### Code Quality

```bash
# Static analysis
mix credo

# Type checking
mix dialyzer

# Generate documentation
mix docs
```

## 🏗️ Architecture

LivekitexAgent follows OTP design principles with a fault-tolerant supervision tree:

```
LivekitexAgent.Application
├── LivekitexAgent.ToolRegistry
│   └── Global function tool registry
└── LivekitexAgent.WorkerSupervisor (per worker pool)
    ├── LivekitexAgent.WorkerManager
    │   └── Job distribution and load balancing
    ├── LivekitexAgent.HealthServer
    │   └── HTTP health check endpoints
    └── Agent Sessions (dynamic)
        ├── AgentSession (GenServer per conversation)
        ├── STTClient (optional, per session)
        ├── TTSClient (optional, per session)
        └── VADClient (optional, per session)
```

### Key Design Principles

- **Fault Tolerance**: Each session runs in an isolated process
- **Scalability**: Dynamic supervision of concurrent sessions
- **Modularity**: Pluggable STT/TTS/VAD providers
- **Performance**: Sub-100ms audio processing pipeline
- **Monitoring**: Built-in metrics and health checks

### Core Modules

| Module | Purpose |
|--------|---------|
| `LivekitexAgent.Agent` | Agent configuration and capabilities |
| `LivekitexAgent.AgentSession` | Session lifecycle, events, and state management |
| `LivekitexAgent.FunctionTool` | Function tool definitions and registry |
| `LivekitexAgent.ToolRegistry` | Global tool registration and discovery |
| `LivekitexAgent.RunContext` | Tool execution context and logging |
| `LivekitexAgent.JobContext` | Job lifecycle and participant management |
| `LivekitexAgent.WorkerManager` | Job distribution and load balancing |
| `LivekitexAgent.WorkerSupervisor` | OTP supervision for worker pools |
| `LivekitexAgent.HealthServer` | HTTP health check endpoints |

### Media Processing Modules

| Module | Purpose |
|--------|---------|
| `LivekitexAgent.Media.AudioProcessor` | PCM16 audio stream processing |
| `LivekitexAgent.Media.VAD` | Voice Activity Detection |
| `LivekitexAgent.Media.SpeechHandle` | Speech interruption control |
| `LivekitexAgent.Media.StreamManager` | Multi-modal stream coordination |

### Provider Integration

| Module | Purpose |
|--------|---------|
| `LivekitexAgent.Providers.OpenAI.LLM` | OpenAI language model integration |
| `LivekitexAgent.Providers.OpenAI.STT` | OpenAI speech-to-text |
| `LivekitexAgent.Providers.OpenAI.TTS` | OpenAI text-to-speech |
| `LivekitexAgent.Realtime.ConnectionManager` | LiveKit room connections |
| `LivekitexAgent.Realtime.WebRTCHandler` | WebRTC audio processing |

## 🔍 Troubleshooting

### Common Issues

**Audio Format**: Always use PCM16 mono 16kHz audio. Convert other formats before streaming.

**API Keys**: Set `OPENAI_API_KEY` environment variable for OpenAI integration.

**macOS Audio**: Ensure `afplay` is available for built-in audio playback.

**Memory Usage**: Monitor session count - each session runs in its own process.

### Performance Tuning

**Latency**: Optimize audio buffer sizes for your latency requirements (target: <100ms).

**Concurrency**: Adjust `max_concurrent_jobs` based on your server capacity.

**Circuit Breaker**: Configure failure thresholds for external API calls.

### Debugging

Enable verbose logging in development:

```elixir
# In your session configuration
event_callbacks: %{
  audio_received: fn _evt, data ->
    Logger.debug("Audio chunk: #{byte_size(data.audio)} bytes")
  end,
  response_delta: fn _evt, data ->
    Logger.debug("Response delta: #{data.text}")
  end
}
```

## 🚀 Phoenix Integration

LivekitexAgent integrates seamlessly with Phoenix applications for web-based voice interfaces:

### LiveView Integration

```elixir
defmodule MyAppWeb.VoiceAgentLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    # Start agent session
    agent = LivekitexAgent.Agent.new(
      instructions: "You are a helpful customer service agent.",
      tools: [:get_product_info, :create_order]
    )

    {:ok, session_pid} = LivekitexAgent.AgentSession.start_link(
      agent: agent,
      event_callbacks: %{
        response_complete: fn _evt, data ->
          send(self(), {:agent_response, data.text})
        end
      }
    )

    {:ok, assign(socket, agent_session: session_pid, messages: [])}
  end

  def handle_event("send_message", %{"message" => text}, socket) do
    LivekitexAgent.AgentSession.process_text(socket.assigns.agent_session, text)
    messages = socket.assigns.messages ++ [%{role: :user, content: text}]
    {:noreply, assign(socket, messages: messages)}
  end

  def handle_info({:agent_response, text}, socket) do
    messages = socket.assigns.messages ++ [%{role: :assistant, content: text}]
    {:noreply, assign(socket, messages: messages)}
  end
end
```

### WebSocket API

```elixir
defmodule MyAppWeb.VoiceSocket do
  use Phoenix.Socket

  channel "voice:*", MyAppWeb.VoiceChannel

  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end
end

defmodule MyAppWeb.VoiceChannel do
  use MyAppWeb, :channel

  def join("voice:" <> session_id, _payload, socket) do
    # Create agent session for this WebSocket connection
    agent = LivekitexAgent.Agent.new(
      instructions: "You are a helpful assistant.",
      tools: [:search_database]
    )

    {:ok, agent_session} = LivekitexAgent.AgentSession.start_link(
      agent: agent,
      event_callbacks: %{
        response_complete: fn _evt, data ->
          push(socket, "agent_response", %{text: data.text})
        end
      }
    )

    Registry.register(MyApp.AgentRegistry, session_id, agent_session)
    {:ok, socket}
  end

  def handle_in("send_audio", %{"audio" => audio_b64}, socket) do
    session_id = socket.topic |> String.split(":") |> List.last()

    case Registry.lookup(MyApp.AgentRegistry, session_id) do
      [{agent_session, _}] ->
        audio = Base.decode64!(audio_b64)
        LivekitexAgent.AgentSession.stream_audio(agent_session, audio)
        {:reply, :ok, socket}
      _ ->
        {:reply, {:error, %{reason: "session_not_found"}}, socket}
    end
  end

  def handle_in("commit_audio", _payload, socket) do
    session_id = socket.topic |> String.split(":") |> List.last()

    case Registry.lookup(MyApp.AgentRegistry, session_id) do
      [{agent_session, _}] ->
        LivekitexAgent.AgentSession.commit_audio(agent_session)
        {:reply, :ok, socket}
      _ ->
        {:reply, {:error, %{reason: "session_not_found"}}, socket}
    end
  end
end
```

## 📚 API Reference

For detailed API documentation, run:

```bash
mix docs
```

Then open `doc/index.html` in your browser.

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Documentation**: [View API docs](https://hexdocs.pm/livekitex_agent)
- **Issues**: [GitHub Issues](https://github.com/livekitex_agent/issues)
- **Discussions**: [GitHub Discussions](https://github.com/livekitex_agent/discussions)

## 🙏 Acknowledgments

- [LiveKit](https://livekit.io/) for the real-time infrastructure
- [OpenAI](https://openai.com/) for AI model integration
- The Elixir community for OTP and Phoenix frameworks