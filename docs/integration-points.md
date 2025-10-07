# LivekitexAgent Integration Points

## Overview

LivekitexAgent integrates with external systems through well-defined integration points that enable real-time voice AI agent functionality. The system leverages multiple APIs and protocols to deliver seamless voice conversations.

## Core Integration Architecture

### 1. LiveKit Integration (WebRTC & Signaling)

#### Connection Management
**Module**: `LivekitexAgent.Realtime.WebRTCHandler`
**Protocol**: WebRTC over LiveKit infrastructure
**Purpose**: Real-time audio/video streaming and participant management

**Key Features**:
- WebRTC connection management through LiveKit infrastructure
- Real-time audio/video stream handling
- Peer connection lifecycle management
- ICE candidate and SDP offer/answer processing
- STUN/TURN server integration via LiveKit
- DataChannel support for control messages
- Connection quality monitoring and adaptation

**Integration Flow**:
```elixir
# LiveKit room connection
webrtc_opts = [
  room_name: "agent-room-123",
  participant_identity: "voice-agent-1",
  livekit_url: "wss://myproject.livekit.cloud",
  api_key: "api_key",
  api_secret: "api_secret",
  audio_enabled: true,
  video_enabled: false
]

{:ok, handler} = LivekitexAgent.Realtime.WebRTCHandler.start_link(webrtc_opts)
```

**Configuration Points**:
- Server URL: WebSocket endpoint for LiveKit server
- API credentials: Key/secret pairs for authentication
- Room management: Dynamic room creation and participant joining
- Media settings: Audio/video track configuration
- Connection options: Timeout, auto-reconnect, quality adaptation

#### Audio Stream Processing
**Performance**: Sub-100ms audio latency for real-time conversations
**Format**: PCM16 mono at configurable sample rates (typically 16kHz)
**Features**:
- Adaptive bitrate for varying network conditions
- Built-in connection redundancy and failover
- Quality adaptation based on network conditions
- Cross-platform compatibility (web, mobile, desktop)

### 2. OpenAI API Integration

#### 2.1 OpenAI Realtime API (WebSocket)
**Module**: `LivekitexAgent.RealtimeWSClient`
**Protocol**: WebSocket with JSON messaging
**Endpoint**: `wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17`

**Key Features**:
- Real-time audio and text conversation handling
- Bidirectional streaming for low-latency interactions
- Function calling integration
- Voice Activity Detection coordination
- Speech interruption support

**Message Types**:
```elixir
# Client → Server
%{
  "type" => "input_audio_buffer.append",
  "audio" => base64_pcm16_audio
}

%{
  "type" => "input_audio_buffer.commit"
}

%{
  "type" => "response.create",
  "response" => %{
    "modalities" => ["text", "audio"],
    "instructions" => "Respond helpfully"
  }
}

# Server → Client
%{
  "type" => "response.audio.delta",
  "delta" => base64_audio_chunk
}

%{
  "type" => "conversation.item.input_audio_transcription.completed",
  "transcript" => "user speech text"
}
```

**Configuration**:
```elixir
realtime_config = %{
  url: "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17",
  api_key: System.get_env("OPENAI_API_KEY"),
  headers: [
    {"Authorization", "Bearer #{api_key}"},
    {"OpenAI-Beta", "realtime=v1"},
    {"Sec-WebSocket-Protocol", "realtime"}
  ],
  sample_rate: 16_000,
  log_frames: true
}
```

#### 2.2 OpenAI REST API Integration

##### Language Model (LLM)
**Module**: `LivekitexAgent.Providers.OpenAI.LLM`
**Endpoint**: `https://api.openai.com/v1/chat/completions`
**Purpose**: Text generation and function calling

**Features**:
- GPT-4 and GPT-3.5-turbo model support
- Function calling with tool definitions
- Streaming and non-streaming responses
- Temperature and generation parameter control
- Token usage tracking and conversation history

**Request Format**:
```elixir
%{
  "model" => "gpt-4-turbo-preview",
  "messages" => [
    %{"role" => "system", "content" => "You are a helpful assistant"},
    %{"role" => "user", "content" => "Hello!"}
  ],
  "tools" => [
    %{
      "type" => "function",
      "function" => %{
        "name" => "get_weather",
        "description" => "Get weather for location",
        "parameters" => %{
          "type" => "object",
          "properties" => %{
            "location" => %{"type" => "string"}
          }
        }
      }
    }
  ],
  "temperature" => 0.7,
  "max_tokens" => 1000
}
```

##### Speech-to-Text (STT)
**Module**: `LivekitexAgent.Providers.OpenAI.STT`
**Endpoint**: `https://api.openai.com/v1/audio/transcriptions`
**Purpose**: Audio transcription using Whisper

**Features**:
- Whisper model integration (whisper-1)
- Multiple audio format support (PCM16, MP3, WAV)
- Language detection and specification
- Timestamp and confidence scoring
- Real-time transcription buffering

**Request Format**:
```elixir
# Multipart form data
%{
  "file" => audio_file_data,
  "model" => "whisper-1",
  "language" => "en",
  "response_format" => "json",
  "temperature" => 0
}
```

##### Text-to-Speech (TTS)
**Module**: `LivekitexAgent.Providers.OpenAI.TTS`
**Endpoint**: `https://api.openai.com/v1/audio/speech`
**Purpose**: Text to speech conversion

**Features**:
- TTS-1 and TTS-1-HD model support
- Multiple voice options (alloy, echo, fable, onyx, nova, shimmer)
- Format options (mp3, opus, aac, flac, wav, pcm)
- Speed control and quality settings
- Streaming response support

**Request Format**:
```elixir
%{
  "model" => "tts-1",
  "input" => "Hello, this is a test message",
  "voice" => "alloy",
  "response_format" => "pcm",
  "speed" => 1.0
}
```

### 3. WebSocket Communication Stack

#### WebSockex Integration
**Library**: `websockex` - Pure Elixir WebSocket client
**Purpose**: Reliable WebSocket connections for real-time communication

**Usage Patterns**:
```elixir
# OpenAI Realtime WebSocket
defmodule LivekitexAgent.RealtimeWSClient do
  use WebSockex

  def handle_connect(_conn, state) do
    Logger.info("RealtimeWS connected")
    {:ok, %{state | connected?: true}}
  end

  def handle_frame({:text, msg}, state) do
    data = Jason.decode!(msg)
    send(state.parent, {:realtime_event, data})
    {:ok, state}
  end
end
```

**Connection Management**:
- Automatic reconnection handling
- Heartbeat/ping support
- Connection state monitoring
- Error recovery patterns
- Frame logging for debugging

### 4. HTTP Client Integration

#### HTTPoison + Hackney Stack
**Libraries**: `httpoison` (interface) + `hackney` (HTTP client)
**Purpose**: REST API calls to external services

**Configuration**:
```elixir
# HTTP request with authentication
headers = [
  {"Authorization", "Bearer #{api_key}"},
  {"Content-Type", "application/json"},
  {"User-Agent", "LivekitexAgent/0.1 (Elixir)"}
]

HTTPoison.post(
  "https://api.openai.com/v1/chat/completions",
  Jason.encode!(request_body),
  headers,
  timeout: 30_000,
  recv_timeout: 60_000
)
```

**Features**:
- Connection pooling for performance
- Request/response timeout handling
- Retry logic for failed requests
- SSL/TLS configuration
- Proxy support when needed

### 5. JSON Data Processing

#### Jason Integration
**Library**: `jason` - Fast JSON encoder/decoder
**Purpose**: Data serialization for API communication

**Usage Patterns**:
```elixir
# Encoding for API requests
request_data = %{
  "model" => "gpt-4",
  "messages" => messages,
  "tools" => tool_definitions
}
json_body = Jason.encode!(request_data)

# Decoding API responses
{:ok, response_data} = Jason.decode(response_body)
```

## Data Flow Integration Patterns

### 1. Session Initialization Flow
```
WorkerOptions → JobContext → AgentSession → LiveKit Room Connection
                ↓
            OpenAI Provider Setup → Function Tool Registry Lookup
```

### 2. Real-time Conversation Flow
```
Audio Input → LiveKit WebRTC → AgentSession
      ↓
  OpenAI Realtime WebSocket → LLM Processing → Tool Execution
      ↓
  Response Generation → TTS → Audio Output → LiveKit WebRTC
```

### 3. Function Tool Execution Flow
```
Tool Call Request → FunctionTool Registry → Parameter Validation
      ↓
  Tool Execution (RunContext) → Result Processing → Response Integration
```

## Configuration Management

### Environment Variables

#### Required Variables
```bash
# LiveKit Configuration
export LIVEKIT_URL="wss://myproject.livekit.cloud"
export LIVEKIT_API_KEY="your-api-key"
export LIVEKIT_API_SECRET="your-api-secret"

# OpenAI Configuration
export OPENAI_API_KEY="your-openai-key"
export OAI_REALTIME_URL="wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17"
```

#### Optional Configuration
```bash
# OpenAI Settings
export OPENAI_BASE_URL="https://api.openai.com/v1"
export OPENAI_LLM_MODEL="gpt-4-turbo-preview"
export OPENAI_STT_MODEL="whisper-1"
export OPENAI_TTS_MODEL="tts-1"
export OPENAI_TTS_VOICE="alloy"

# Performance Tuning
export MAX_CONCURRENT_JOBS="10"
export CONNECTION_TIMEOUT="30000"
export REQUEST_TIMEOUT="60000"
```

### Configuration Files

#### Development Environment (`config/dev.exs`)
```elixir
config :livekitex_agent,
  livekit: [
    server_url: System.get_env("LIVEKIT_URL") || "ws://localhost:7880",
    api_key: System.get_env("LIVEKIT_API_KEY") || "devkey",
    api_secret: System.get_env("LIVEKIT_API_SECRET") || "secret"
  ],
  openai: [
    api_key: System.get_env("OPENAI_API_KEY"),
    base_url: "https://api.openai.com/v1",
    llm_model: "gpt-4-turbo-preview"
  ]
```

#### Production Environment (`config/prod.exs` + `config/runtime.exs`)
```elixir
# Strict environment variable requirements
config :livekitex_agent,
  livekit: [
    server_url: System.get_env("LIVEKIT_URL") ||
                raise("LIVEKIT_URL environment variable is required"),
    api_key: System.get_env("LIVEKIT_API_KEY") ||
             raise("LIVEKIT_API_KEY environment variable is required")
  ]
```

## Integration Security

### Authentication Methods

#### LiveKit Authentication
- API Key/Secret pair for server authentication
- JWT token generation for room access
- Participant identity verification

#### OpenAI Authentication
- Bearer token authentication for REST APIs
- WebSocket connection authentication with headers
- API key rotation support

### Network Security
- TLS/SSL enforcement for all connections
- Certificate validation for WebSocket connections
- Secure credential storage and retrieval

## Performance Characteristics

### Latency Optimization
- **LiveKit**: Sub-100ms audio latency through WebRTC
- **OpenAI Realtime**: Low-latency streaming responses
- **Connection Pooling**: Reduced connection establishment overhead

### Scalability Features
- **Concurrent Connections**: Multiple simultaneous LiveKit rooms
- **Load Balancing**: Request distribution across worker pools
- **Circuit Breakers**: Fault tolerance for API failures

### Monitoring Integration
- **Health Checks**: HTTP endpoints for system status
- **Metrics Collection**: Performance and usage tracking
- **Error Reporting**: Structured logging and error handling

This integration architecture enables LivekitexAgent to provide robust, real-time voice AI agent functionality while maintaining flexibility for different deployment scenarios and external service configurations.