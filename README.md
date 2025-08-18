# LivekitexAgent

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `livekitex_agent` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:livekitex_agent, "~> 0.1.0"}
  ]
end
```
# LivekitexAgent

An Elixir library that replicates LiveKit Agents functionality for voice agents, providing a comprehensive suite of tools for building conversational AI applications.

## Features

- **Agent Management**: Create and configure voice agents with instructions, tools, and behavioral settings
- **Session Handling**: Manage real-time agent sessions with speech processing and conversation flow
- **Job Context**: Handle job execution with participant management and async task coordination
- **Worker Management**: Configure and run agent workers with load balancing and health monitoring
- **Function Tools**: Define and execute LLM-callable functions with automatic schema generation
- **CLI Interface**: Command-line tools for running agents in development and production modes

## Installation

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

## Quick Start

### 1. Create an Agent

```elixir
# Create a voice agent with basic configuration
agent = LivekitexAgent.Agent.new([
  instructions: "You are a helpful voice assistant. Be concise and friendly.",
  tools: [:get_weather, :add_numbers, :search_web],
  agent_id: "my_voice_agent"
])
```

### 2. Start an Agent Session

```elixir
# Start a session for real-time interactions
{:ok, session_pid} = LivekitexAgent.AgentSession.start_link([
  agent: agent,
  event_callbacks: %{
    session_started: &handle_session_started/2,
    text_received: &handle_text_received/2
  }
])

# Process user input
LivekitexAgent.AgentSession.process_text(session_pid, "What's the weather like?")
```

### 3. Define Function Tools

```elixir
defmodule MyTools do
  use LivekitexAgent.FunctionTool

  @tool "Get weather information for a location"
  @spec get_weather(String.t()) :: String.t()
  def get_weather(location) do
    "Weather in #{location}: Sunny, 25°C"
  end

  @tool "Search for information with context"
  @spec search_web(String.t(), LivekitexAgent.RunContext.t()) :: String.t()
  def search_web(query, context) do
    LivekitexAgent.RunContext.log_info(context, "Searching: #{query}")
    "Search results for #{query}"
  end
end

# Register the tools
LivekitexAgent.FunctionTool.register_module(MyTools)
```

### 4. Configure and Start a Worker

```elixir
# Define job entry point
entry_point = fn job_context ->
  agent = LivekitexAgent.Agent.new([
    instructions: "You are a helpful assistant"
  ])

  {:ok, session} = LivekitexAgent.AgentSession.start_link(agent: agent)
  # Handle the session...
end

# Create worker options
worker_options = LivekitexAgent.WorkerOptions.new([
  entry_point: entry_point,
  agent_name: "my_agent",
  server_url: "wss://your-livekit-server.com",
  api_key: "your-api-key",
  max_concurrent_jobs: 5
])

# Start the worker
{:ok, _pid} = LivekitexAgent.WorkerSupervisor.start_link(worker_options)
```

### 5. CLI Usage

```bash
# Start in development mode
mix run -e "LivekitexAgent.CLI.main(['dev', '--hot-reload', '--log-level', 'debug'])"

# Start in production mode
mix run -e "LivekitexAgent.CLI.main(['start', '--agent-name', 'prod_agent', '--production'])"

# Check health
mix run -e "LivekitexAgent.CLI.main(['health'])"
```

## Core Modules

### LivekitexAgent.Agent

The main agent configuration that encapsulates behavior, tools, and settings:

- **Instructions**: Guide agent behavior
- **Tools**: Available function tools
- **Components**: STT, TTS, LLM, VAD configuration
- **Settings**: Turn detection, interruption handling

### LivekitexAgent.AgentSession

Runtime orchestration for voice agents:

- **Media Streams**: Audio, video, text I/O management
- **Speech Processing**: STT, TTS, VAD integration
- **Tool Execution**: Multi-step function calls
- **Event System**: Callbacks for session events

### LivekitexAgent.JobContext

Job execution context and resource management:

- **Room Management**: LiveKit room access
- **Participant Handling**: User connection management
- **Task Management**: Async task coordination
- **Logging**: Contextual logging with job fields

### LivekitexAgent.RunContext

Function tool execution context:

- **Session Access**: Current agent session
- **Speech Control**: Control speech generation
- **Function Info**: Current function call details
- **User Data**: Session-specific data access

### LivekitexAgent.WorkerOptions

Worker configuration and management:

- **Entry Points**: Job handling functions
- **Load Balancing**: Load calculation and thresholds
- **Connection Settings**: LiveKit server configuration
- **Process Management**: Memory limits, timeouts

### LivekitexAgent.FunctionTool

LLM function tool system:

- **Auto-discovery**: Tool registration via attributes
- **Schema Generation**: OpenAI-compatible function schemas
- **Parameter Handling**: Type validation and conversion
- **Execution**: Safe tool execution with error handling

## Examples

See `LivekitexAgent.Example` module for comprehensive usage examples:

```elixir
# Run the complete example
{:ok, result} = LivekitexAgent.Example.run_complete_example()

# Demonstrate individual components
LivekitexAgent.Example.demonstrate_tools()
agent = LivekitexAgent.Example.create_simple_agent()
```

## Configuration

Create a configuration file for production deployments:

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

Load with:

```bash
mix run -e "LivekitexAgent.CLI.main(['start', '--config-file', './config/production.json'])"
```

## Testing

Run the test suite:

```bash
mix test
```

Run with coverage:

```bash
mix test --cover
```

## Development

1. Clone the repository
2. Install dependencies: `mix deps.get`
3. Run tests: `mix test`
4. Start development mode: `iex -S mix`

### Code Quality

- **Credo**: `mix credo`
- **Dialyzer**: `mix dialyzer`
- **Documentation**: `mix docs`

## Architecture

The library follows OTP principles with supervision trees and fault tolerance:

```
LivekitexAgent.Application
├── LivekitexAgent.ToolRegistry (global tool registry)
└── LivekitexAgent.WorkerSupervisor (per worker)
    ├── LivekitexAgent.WorkerManager (job distribution)
    └── LivekitexAgent.HealthServer (health checks)
```

Each agent session runs as a supervised GenServer, and jobs are executed in isolated processes with proper error handling and resource management.

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass (`mix test`)
6. Run code quality checks (`mix credo`, `mix dialyzer`)
7. Commit your changes (`git commit -am 'Add amazing feature'`)
8. Push to the branch (`git push origin feature/amazing-feature`)
9. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Inspired by LiveKit Agents Python library
- Built with Elixir/OTP for fault tolerance and scalability
- Designed for production voice AI applications

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/livekitex_agent>.
