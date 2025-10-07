# LivekitexAgent System Components Analysis

## Overview

The LivekitexAgent system is a comprehensive Elixir library that replicates LiveKit Agents functionality for voice AI agents. It follows the Actor Model with OTP supervision trees and provides a robust, scalable architecture.

## Core System Components

### 1. LivekitexAgent.Agent
**File**: `lib/livekitex_agent/agent.ex`
**Type**: GenServer with state management
**Purpose**: Agent configuration and lifecycle management

**Key Features**:
- Agent lifecycle management with state transitions (`:created`, `:configured`, `:active`, `:inactive`, `:destroyed`)
- Configuration validation and updates
- Tool registration and management
- Provider configuration (STT, TTS, LLM, VAD)
- Performance metrics and monitoring
- Event system integration
- Graceful shutdown handling

**Data Structure**:
```elixir
%LivekitexAgent.Agent{
  agent_id: String.t(),
  instructions: String.t(),
  tools: list(atom()),
  llm_config: map(),
  stt_config: map(),
  tts_config: map(),
  vad_config: map(),
  metadata: map(),
  state: :created | :configured | :active | :inactive | :destroyed,
  metrics: map(),
  event_callbacks: map()
}
```

### 2. LivekitexAgent.AgentSession
**File**: `lib/livekitex_agent/agent_session.ex`
**Type**: GenServer orchestrating real-time components
**Purpose**: Runtime orchestration of voice agent components

**Key Features**:
- Media streams coordination
- Speech/LLM components integration
- Tool orchestration and execution
- Turn detection and endpointing
- Interruption handling
- Multi-step tool calls
- Audio, video, and text I/O management
- Comprehensive event callbacks system (25+ event types)
- Real-time voice agent lifecycle

**Event Categories**:
- Session Lifecycle: `:session_started`, `:session_stopped`, `:state_changed`
- Audio Processing: `:audio_received`, `:audio_streamed`, `:tts_audio`
- Speech Recognition: `:stt_result`, `:vad_speech_start`, `:vad_speech_end`
- Conversation: `:text_received`, `:response_generated`, `:turn_started`
- Tool Execution: `:tool_called`, `:tool_completed`, `:tool_error`
- Interruption: `:interrupted`, `:response_cancelled`
- LiveKit Integration: `:room_id_updated`, `:realtime_event`

### 3. LivekitexAgent.WorkerManager
**File**: `lib/livekitex_agent/worker_manager.ex`
**Type**: GenServer with enterprise job distribution
**Purpose**: Worker processes and job distribution management

**Key Features**:
- Job distribution across worker pool with configurable load balancing
- Worker health monitoring and automatic recovery
- Dynamic worker pool scaling based on load metrics
- Circuit breaker pattern for handling failures
- Job queuing with backpressure control
- Graceful shutdown with job completion handling
- Comprehensive metrics collection and reporting

**Load Balancing Strategies**:
- `:round_robin` - Equal distribution
- `:least_connections` - Least busy worker
- `:weighted_round_robin` - Weighted distribution
- `:load_based` - Based on system metrics

### 4. LivekitexAgent.FunctionTool
**File**: `lib/livekitex_agent/function_tool.ex`
**Type**: Macro system with runtime registry
**Purpose**: Function tool definitions and LLM integration

**Key Features**:
- Auto-discovery of tool functions through `@tool` attributes
- Automatic schema generation from function signatures
- Parameter handling and conversion to LLM-compatible format
- Raw tools support for custom function descriptions
- Tool registry management
- RunContext integration for session access

**Usage Pattern**:
```elixir
defmodule MyTools do
  use LivekitexAgent.FunctionTool

  @tool "Get weather information for a location"
  @spec get_weather(String.t()) :: String.t()
  def get_weather(location) do
    "Weather in " <> location <> ": Sunny, 25°C"
  end
end
```

### 5. LivekitexAgent.ToolRegistry
**File**: `lib/livekitex_agent/tool_registry.ex`
**Type**: GenServer with ETS table storage
**Purpose**: Dynamic tool registration and discovery

**Key Features**:
- Dynamic tool registration and deregistration
- Tool discovery by name or metadata
- Tool validation and schema generation
- Performance metrics for tool usage
- Event notifications for registry changes

### 6. LivekitexAgent.JobContext
**File**: `lib/livekitex_agent/job_context.ex`
**Type**: GenServer managing job lifecycle
**Purpose**: Context and resources for agent job execution

**Key Features**:
- Room management and LiveKit room access
- Process information about running jobs
- Connection and shutdown event handlers
- Participant handling and entry points
- Async task management within jobs
- Contextual logging with job-specific fields

**Job Status States**: `:created` → `:running` → `:completed` | `:failed` | `:terminated`

### 7. LivekitexAgent.RunContext
**File**: `lib/livekitex_agent/run_context.ex`
**Type**: Data structure for tool execution
**Purpose**: Context object for function tool execution

**Key Features**:
- Access to current AgentSession
- Speech handle for controlling speech generation
- Function call information
- Access to session-specific user data
- Utilities for tool execution logging and metrics

### 8. LivekitexAgent.WorkerOptions
**File**: `lib/livekitex_agent/worker_options.ex`
**Type**: Configuration struct
**Purpose**: Worker behavior and job execution configuration

**Key Features**:
- Entry point function configuration
- Request handling logic for job acceptance
- Process management settings
- Load balancing configuration
- Connection settings (LiveKit server URL, API credentials)
- Agent settings (name, permissions, worker type)
- Enterprise features (auto-scaling, circuit breakers, rate limiting)

**Worker Types**: `:voice_agent`, `:multimodal_agent`, `:text_agent`, `:custom`

### 9. LivekitexAgent.WorkerSupervisor
**File**: `lib/livekitex_agent/worker_supervisor.ex`
**Type**: OTP Supervisor
**Purpose**: Supervision and job execution coordination

**Key Features**:
- Dynamic worker process supervision
- Job type handling (`:agent_session`, `:tool_execution`, `:audio_processing`)
- Process lifecycle management
- Fault tolerance and recovery
- Performance monitoring

### 10. LivekitexAgent.HealthServer
**File**: `lib/livekitex_agent/health_server.ex`
**Type**: HTTP server GenServer
**Purpose**: Health checks and system metrics

**Key Features**:
- HTTP endpoints for health monitoring
- Kubernetes readiness/liveness probes
- Prometheus-compatible metrics
- Detailed system status reporting
- Lightweight implementation for fast startup

**Endpoints**:
- `GET /health` - Basic health check
- `GET /health/ready` - Readiness probe
- `GET /health/live` - Liveness probe
- `GET /metrics` - Prometheus metrics
- `GET /status` - Detailed system status

### 11. LivekitexAgent.CLI
**File**: `lib/livekitex_agent/cli.ex`
**Type**: Command-line interface
**Purpose**: Agent management and deployment utilities

**Key Features**:
- Production mode worker startup
- Development options with hot reload
- Configuration management
- Worker management with graceful shutdown
- Enterprise deployment commands
- Tool testing and validation

**Command Categories**:
- Basic: `start`, `dev`, `worker`, `test`, `config`, `health`
- Enterprise: `deploy`, `cluster`, `scale`, `monitor`, `metrics`, `dashboard`
- Tools: `tools`, `test-tool`, `list-tools`, `validate-tools`

### 12. LivekitexAgent.Application
**File**: `lib/livekitex_agent/application.ex`
**Type**: OTP Application
**Purpose**: Application supervision tree and initialization

**Key Features**:
- Core component initialization
- Supervision tree setup
- Graceful shutdown coordination
- Telemetry integration
- Configuration-based component startup

## System Architecture Patterns

### Supervision Tree Structure
```
LivekitexAgent.Supervisor
├── LivekitexAgent.ToolRegistry (ETS-based registry)
├── LivekitexAgent.ShutdownManager (graceful shutdown)
├── LivekitexAgent.WorkerManager (job distribution)
├── LivekitexAgent.HealthServer (monitoring)
└── LivekitexAgent.WorkerSupervisor (dynamic workers)
    └── [Dynamic Agent Sessions...]
```

### Data Flow Patterns

#### Session Initialization Flow
1. `WorkerOptions` → `JobContext` creation
2. `JobContext` → `AgentSession` spawn
3. `AgentSession` → `Agent` configuration load
4. `Agent` → `FunctionTool` registry lookup
5. `AgentSession` → LiveKit room connection
6. Room connection → Participant discovery

#### Tool Execution Flow
1. `AgentSession` receives tool call request
2. Create `RunContext` with session reference
3. `FunctionTool` registry lookup by name
4. Parameter validation against tool schema
5. Tool execution with `RunContext`
6. Result returned to `AgentSession`
7. Response sent through LiveKit connection

### Integration Points

#### LiveKit Integration
- WebSocket connections through `livekitex` library
- Room management and participant handling
- Audio/video stream processing
- Real-time communication protocol

#### OpenAI Integration
- LLM integration for conversation handling
- STT (Speech-to-Text) processing
- TTS (Text-to-Speech) synthesis
- Function calling API compatibility

#### External Dependencies
- `websockex` for WebSocket communication
- `httpoison` for HTTP requests
- `hackney` for HTTP client
- `jason` for JSON handling
- `timex` for time management

## Storage and State Management

### ETS Tables
- Tool registry storage (in-memory, fast access)
- Session state caching
- Metrics collection

### Process State
- Agent configuration in GenServer state
- Session state with conversation history
- Job context with participant tracking
- Worker manager with pool status

### Persistence
- Configuration files for deployment settings
- Log files for debugging and monitoring
- Optional external storage for session history (not implemented in current version)

## Performance Characteristics

### Scalability Features
- Dynamic worker pool scaling
- Load-based job distribution
- Circuit breaker pattern for fault tolerance
- Backpressure control for queue management

### Monitoring and Metrics
- Comprehensive telemetry integration
- Health check endpoints for orchestration
- Performance metrics collection
- Real-time status reporting

### Enterprise Features
- Multi-worker deployment
- Graceful shutdown handling
- Resource limit management
- Distributed system support

This analysis provides the foundation for understanding how LivekitexAgent components interact and the overall system architecture for voice AI agent functionality.