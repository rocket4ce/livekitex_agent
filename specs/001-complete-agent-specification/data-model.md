# Data Model: LivekitexAgent

## Core Entities

### Agent

**Purpose**: Central configuration entity representing a voice AI agent

**Fields**:
- `agent_id`: String - Unique identifier for the agent
- `instructions`: String - System prompt/instructions for LLM behavior
- `tools`: List of Atoms - Available function tools by name
- `llm_config`: Map - LLM provider configuration (model, temperature, etc.)
- `stt_config`: Map - Speech-to-Text provider configuration
- `tts_config`: Map - Text-to-Speech provider configuration
- `vad_config`: Map - Voice Activity Detection configuration
- `metadata`: Map - Custom metadata for agent extensions
- `created_at`: DateTime - Agent creation timestamp
- `updated_at`: DateTime - Last configuration update

**Validation Rules**:
- `agent_id` must be unique, non-empty string, max 255 chars
- `instructions` required, max 10,000 characters
- `tools` must reference registered function tools
- Config maps must validate against provider schemas
- All timestamps must be valid DateTime structs

**State Transitions**:
- Created → Configured → Active → Inactive → Destroyed
- Configuration updates allowed in any non-destroyed state

### AgentSession

**Purpose**: Active conversation session between agent and participants

**Fields**:
- `session_id`: String - Unique session identifier
- `agent`: Agent struct - Associated agent configuration
- `room_id`: String - LiveKit room identifier
- `participants`: Map - Connected participants by ID
- `conversation_state`: Map - Current conversation context
- `audio_state`: Map - Audio processing state (muted, VAD status, etc.)
- `metrics`: Map - Session performance metrics
- `event_callbacks`: Map - Registered event handlers
- `user_data`: Map - Session-specific user data
- `status`: Atom - Current session status
- `started_at`: DateTime - Session start time
- `last_activity_at`: DateTime - Last interaction timestamp

**Validation Rules**:
- `session_id` must be unique, generated automatically
- `agent` must be valid Agent struct
- `room_id` required for LiveKit integration
- `status` must be one of: `:initializing`, `:connected`, `:active`, `:paused`, `:disconnected`, `:error`
- Participants map values must be valid Participant structs
- Timestamps must be chronologically consistent

**State Transitions**:
- Initializing → Connected → Active ⇄ Paused → Disconnected
- Error state reachable from any state
- Reconnection possible from Disconnected to Connected

### Participant

**Purpose**: Individual participant in an agent session

**Fields**:
- `participant_id`: String - Unique participant identifier
- `identity`: String - Human-readable participant identity
- `name`: String - Display name
- `kind`: Atom - Participant type (`:standard`, `:sip`, `:agent`)
- `permissions`: Map - Participant permissions and capabilities
- `audio_track`: Map - Audio track information
- `video_track`: Map - Video track information (optional)
- `connection_state`: Atom - Connection status
- `joined_at`: DateTime - When participant joined session
- `metadata`: Map - Custom participant metadata

**Validation Rules**:
- `participant_id` must be unique within session
- `identity` required, non-empty string
- `kind` must be valid ParticipantKind atom
- Connection state must be valid ConnectionState atom
- Track maps must validate against LiveKit schemas

**Relationships**:
- Belongs to AgentSession (many-to-one)
- May have multiple AudioTracks and VideoTracks

### FunctionTool

**Purpose**: Executable function that agents can call

**Fields**:
- `name`: String - Unique tool identifier
- `description`: String - Human-readable tool description
- `module`: Atom - Elixir module containing implementation
- `function`: Atom - Function name within module
- `arity`: Integer - Number of function parameters
- `parameters`: List - Parameter definitions with types and validation
- `return_type`: String - Expected return type
- `timeout`: Integer - Execution timeout in milliseconds
- `schema`: Map - OpenAI function calling schema
- `metadata`: Map - Additional tool metadata

**Validation Rules**:
- `name` must be unique globally, valid identifier format
- `description` required, max 500 characters
- `module` and `function` must exist and be callable
- `arity` must match actual function arity
- Parameters must have valid type definitions
- `timeout` must be positive integer, max 300_000ms (5 minutes)
- Schema must be valid OpenAI function format

**Relationships**:
- Many-to-many with Agent (through tools list)
- Used by RunContext during execution

### JobContext

**Purpose**: Execution context for agent jobs and tasks

**Fields**:
- `job_id`: String - Unique job identifier
- `room`: Map - LiveKit room information
- `participants`: List - Participant identifiers in job
- `tasks`: List - Associated tasks for this job
- `status`: Atom - Current job status
- `assigned_worker`: String - Worker handling this job
- `priority`: Integer - Job priority level
- `created_at`: DateTime - Job creation time
- `started_at`: DateTime - Job execution start
- `completed_at`: DateTime - Job completion time
- `metadata`: Map - Job-specific metadata

**Validation Rules**:
- `job_id` must be unique, non-empty string
- `room` must contain valid LiveKit room data
- `status` must be one of: `:pending`, `:assigned`, `:running`, `:completed`, `:failed`, `:cancelled`
- `priority` must be integer 1-10 (1=highest)
- Timestamps must be chronologically consistent

**State Transitions**:
- Pending → Assigned → Running → Completed/Failed/Cancelled
- Cancellation possible from any pre-completion state

### RunContext

**Purpose**: Execution context passed to function tools during invocation

**Fields**:
- `execution_id`: String - Unique execution identifier
- `session`: PID - AgentSession process identifier
- `speech_handle`: Map - Speech control interface
- `function_call`: Map - Current function call information
- `user_data`: Map - Session user data
- `started_at`: DateTime - Execution start time
- `timeout_at`: DateTime - Execution timeout deadline
- `metadata`: Map - Execution metadata

**Validation Rules**:
- `execution_id` must be unique per tool execution
- `session` must be valid AgentSession PID
- `function_call` must contain name and arguments
- Timestamps must be valid and timeout_at > started_at
- Speech handle must implement SpeechHandle behaviour

**Relationships**:
- Associated with AgentSession during execution
- Passed to FunctionTool implementations
- May reference JobContext for job-level data

### WorkerOptions

**Purpose**: Configuration for agent workers and job processing

**Fields**:
- `agent_name`: String - Worker identifier
- `server_url`: String - LiveKit server WebSocket URL
- `api_key`: String - LiveKit API key
- `api_secret`: String - LiveKit API secret
- `entry_point`: Function - Job entry point function
- `max_concurrent_jobs`: Integer - Maximum simultaneous jobs
- `worker_type`: Atom - Type of worker (`:voice_agent`, `:pipeline`, etc.)
- `region`: String - Deployment region
- `drain_timeout`: Integer - Graceful shutdown timeout
- `health_check_port`: Integer - Health check HTTP port
- `log_level`: Atom - Logging verbosity level

**Validation Rules**:
- `agent_name` must be unique, valid identifier
- `server_url` must be valid WebSocket URL
- API credentials must be non-empty strings
- `entry_point` must be valid function reference
- `max_concurrent_jobs` must be positive integer, max 1000
- `worker_type` must be valid WorkerType atom
- Timeouts must be positive integers
- `log_level` must be valid Logger level

### AudioState

**Purpose**: Audio processing and streaming state

**Fields**:
- `format`: Map - Audio format specification (PCM16, sample rate, channels)
- `vad_enabled`: Boolean - Voice Activity Detection status
- `vad_sensitivity`: Float - VAD sensitivity level (0.0-1.0)
- `is_speaking`: Boolean - Current speaking state
- `is_muted`: Boolean - Audio mute status
- `buffer_size`: Integer - Audio buffer size in samples
- `latency_ms`: Integer - Current processing latency
- `stream_active`: Boolean - Audio stream status
- `last_audio_at`: DateTime - Last audio activity timestamp

**Validation Rules**:
- Format must specify valid audio parameters
- VAD sensitivity must be float between 0.0 and 1.0
- Buffer size must be positive integer
- Latency must be non-negative integer
- Timestamps must be valid DateTime structs

## Entity Relationships

### Primary Relationships

1. **Agent → AgentSession (1:N)**
   - One agent can have multiple active sessions
   - Sessions maintain reference to agent configuration
   - Sessions inherit agent's tool registry and configurations

2. **AgentSession → Participant (1:N)**
   - Sessions contain multiple participants
   - Each participant belongs to exactly one session
   - Participants can be agents, humans, or SIP endpoints

3. **Agent → FunctionTool (N:M)**
   - Agents reference tools by name in tools list
   - Tools can be used by multiple agents
   - Registry maintains global tool definitions

4. **JobContext → AgentSession (1:1)**
   - Each job creates one agent session
   - Session lifecycle managed by job context
   - Job completion triggers session cleanup

5. **RunContext → FunctionTool (1:1)**
   - Each tool execution gets unique run context
   - Context provides session access and execution metadata
   - Context lifecycle limited to tool execution duration

### Dependency Graph

```
WorkerOptions → JobContext → AgentSession → Agent
                    ↓           ↓           ↓
                RunContext → FunctionTool  ←┘
                    ↓           ↓
                Participant ←───┘
                    ↓
                AudioState
```

## Data Flow Patterns

### Session Initialization Flow
1. WorkerOptions → JobContext creation
2. JobContext → AgentSession spawn
3. AgentSession → Agent configuration load
4. Agent → FunctionTool registry lookup
5. AgentSession → LiveKit room connection
6. Room connection → Participant discovery

### Tool Execution Flow
1. AgentSession receives tool call request
2. Create RunContext with session reference
3. FunctionTool registry lookup by name
4. Parameter validation against tool schema
5. Tool execution with RunContext
6. Result returned to AgentSession
7. Response sent through LiveKit connection

### Audio Processing Flow
1. LiveKit audio stream → AgentSession
2. AgentSession → AudioState update
3. VAD processing → speech detection
4. Speech boundaries → conversation turns
5. STT processing → text extraction
6. LLM processing → response generation
7. TTS processing → audio synthesis
8. Audio output → LiveKit stream

This data model supports real-time audio processing requirements while maintaining clear separation of concerns and supporting the agent-centric architecture defined in the constitution.