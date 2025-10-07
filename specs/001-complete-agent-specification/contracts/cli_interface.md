# CLI Interface Specification

## Command Structure

```bash
livekitex_agent [GLOBAL_OPTIONS] <COMMAND> [COMMAND_OPTIONS] [ARGUMENTS]
```

## Global Options

- `-h, --help` - Show help information
- `-v, --version` - Show version information
- `--config FILE` - Load configuration from file
- `--log-level LEVEL` - Set logging level (debug, info, warn, error)

## Commands

### start

Start agent worker in production mode.

**Usage**: `livekitex_agent start [OPTIONS]`

**Options**:
- `--agent-name NAME` - Worker identifier (required)
- `--server-url URL` - LiveKit server WebSocket URL (required)
- `--api-key KEY` - LiveKit API key
- `--api-secret SECRET` - LiveKit API secret
- `--max-jobs N` - Maximum concurrent jobs (default: 10)
- `--worker-type TYPE` - Worker type (voice_agent, pipeline, etc.)
- `--region REGION` - Deployment region
- `--drain-timeout MS` - Graceful shutdown timeout (default: 30000)
- `--health-port PORT` - Health check HTTP port (default: 8080)

**Examples**:
```bash
# Start basic voice agent worker
livekitex_agent start --agent-name my-agent --server-url ws://localhost:7880

# Start with API credentials and custom settings
livekitex_agent start \
  --agent-name production-agent \
  --server-url wss://my-livekit.com \
  --api-key your-api-key \
  --api-secret your-api-secret \
  --max-jobs 50 \
  --region us-west-2
```

**Exit Codes**:
- `0` - Normal shutdown
- `1` - Configuration error
- `2` - Connection error
- `3` - Authentication error

### dev

Start agent worker in development mode with enhanced debugging.

**Usage**: `livekitex_agent dev [OPTIONS]`

**Options**:
- All options from `start` command
- `--hot-reload` - Enable hot code reloading
- `--debug-websocket` - Enable WebSocket debug logging
- `--mock-providers` - Use mock AI providers for testing
- `--record-audio FILE` - Record audio to file for debugging

**Examples**:
```bash
# Start development worker with hot reload
livekitex_agent dev --agent-name dev-agent --hot-reload

# Development with debugging enabled
livekitex_agent dev \
  --agent-name debug-agent \
  --server-url ws://localhost:7880 \
  --debug-websocket \
  --log-level debug
```

### test

Run agent tests and validation.

**Usage**: `livekitex_agent test [OPTIONS] [TEST_PATTERNS]`

**Options**:
- `--integration` - Run integration tests
- `--property` - Run property-based tests
- `--coverage` - Generate coverage report
- `--benchmark` - Run performance benchmarks
- `--mock-server` - Start mock LiveKit server

**Examples**:
```bash
# Run all tests
livekitex_agent test

# Run specific test files
livekitex_agent test test/agent_test.exs test/function_tool_test.exs

# Run integration tests with coverage
livekitex_agent test --integration --coverage
```

### config

Show and validate configuration.

**Usage**: `livekitex_agent config [SUBCOMMAND] [OPTIONS]`

**Subcommands**:
- `show` - Display current configuration
- `validate` - Validate configuration file
- `generate` - Generate sample configuration file

**Options**:
- `--format FORMAT` - Output format (json, yaml, elixir)
- `--output FILE` - Write to file instead of stdout

**Examples**:
```bash
# Show current configuration
livekitex_agent config show

# Validate config file
livekitex_agent config validate --config config/prod.exs

# Generate sample configuration
livekitex_agent config generate --output config/sample.exs
```

### health

Check worker and system health.

**Usage**: `livekitex_agent health [OPTIONS]`

**Options**:
- `--endpoint URL` - Health check endpoint URL
- `--timeout MS` - Request timeout (default: 5000)
- `--format FORMAT` - Output format (json, text)

**Examples**:
```bash
# Check local worker health
livekitex_agent health

# Check remote worker health
livekitex_agent health --endpoint http://worker1.example.com:8080/health
```

### tools

Manage function tools.

**Usage**: `livekitex_agent tools <SUBCOMMAND> [OPTIONS]`

**Subcommands**:
- `list` - List registered tools
- `register MODULE` - Register tools from module
- `test TOOL_NAME` - Test specific tool
- `schema TOOL_NAME` - Show tool OpenAI schema

**Examples**:
```bash
# List all registered tools
livekitex_agent tools list

# Register tools from module
livekitex_agent tools register MyApp.CustomTools

# Test specific tool
livekitex_agent tools test get_weather --args '{"location": "Madrid"}'

# Show tool schema
livekitex_agent tools schema get_weather --format json
```

### session

Interactive session management (development).

**Usage**: `livekitex_agent session [OPTIONS]`

**Options**:
- `--agent-name NAME` - Agent to use for session
- `--room-name NAME` - LiveKit room name
- `--interactive` - Start interactive REPL session

**Examples**:
```bash
# Start interactive session
livekitex_agent session --agent-name test-agent --interactive

# Connect to specific room
livekitex_agent session --room-name my-room --agent-name my-agent
```

## Configuration File Format

Configuration files use Elixir configuration format:

```elixir
# config/prod.exs
import Config

config :livekitex_agent,
  # Worker settings
  agent_name: "production-agent",
  server_url: "wss://livekit.example.com",
  api_key: System.get_env("LIVEKIT_API_KEY"),
  api_secret: System.get_env("LIVEKIT_API_SECRET"),
  max_concurrent_jobs: 50,
  worker_type: :voice_agent,

  # Health check settings
  health_check_port: 8080,
  drain_timeout: 30_000,

  # Logging
  log_level: :info,
  structured_logging: true,

  # AI Provider settings
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
    vad_sensitivity: 0.5
  ]
```

## Environment Variables

The CLI supports environment variable configuration:

- `LIVEKITEX_AGENT_NAME` - Default agent name
- `LIVEKITEX_SERVER_URL` - Default LiveKit server URL
- `LIVEKITEX_API_KEY` - LiveKit API key
- `LIVEKITEX_API_SECRET` - LiveKit API secret
- `LIVEKITEX_LOG_LEVEL` - Default log level
- `LIVEKITEX_CONFIG_FILE` - Default configuration file path

## Output Formats

### JSON Format

```json
{
  "status": "success",
  "data": {
    "agent_name": "my-agent",
    "uptime": 3600,
    "active_sessions": 5,
    "total_jobs": 150
  },
  "timestamp": "2025-10-07T12:00:00Z"
}
```

### Text Format

```
LivekitexAgent Status
====================
Agent Name: my-agent
Uptime: 1h 0m 0s
Active Sessions: 5
Total Jobs: 150
Status: healthy
```

## Error Handling

CLI commands return appropriate exit codes and error messages:

**Exit Codes**:
- `0` - Success
- `1` - General error
- `2` - Configuration error
- `3` - Connection error
- `4` - Authentication error
- `5` - Resource error (out of memory, disk space, etc.)
- `125` - Command not found
- `126` - Command not executable
- `127` - Command not found

**Error Message Format**:
```
ERROR: Configuration validation failed
  - server_url: must be a valid WebSocket URL
  - api_key: is required when api_secret is provided

Use 'livekitex_agent config validate --help' for more information.
```

## Interactive Features

### REPL Session

When using `livekitex_agent session --interactive`, provides:

- Tab completion for commands and function names
- Command history
- Real-time session status updates
- Tool testing capabilities
- Audio playback controls (on supported platforms)

### Hot Reload (Development)

In development mode with `--hot-reload`:
- Automatically recompiles and reloads code changes
- Preserves session state during reloads
- Shows compilation errors and warnings
- Supports tool definition updates without restart

## Integration Examples

### Systemd Service

```ini
[Unit]
Description=LivekitexAgent Worker
After=network.target

[Service]
Type=exec
User=livekitex
Group=livekitex
WorkingDirectory=/opt/livekitex_agent
Environment=LIVEKITEX_CONFIG_FILE=/etc/livekitex_agent/prod.exs
ExecStart=/usr/local/bin/livekitex_agent start
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Docker Deployment

```dockerfile
FROM elixir:1.15-alpine

RUN apk add --no-cache build-base git

WORKDIR /app
COPY . .
RUN mix deps.get && mix compile

EXPOSE 8080
CMD ["livekitex_agent", "start", "--config", "/app/config/docker.exs"]
```

### Kubernetes Health Checks

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```