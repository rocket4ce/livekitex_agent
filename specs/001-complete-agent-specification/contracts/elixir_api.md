# Elixir Module API Contracts

## LivekitexAgent

Main module providing high-level agent operations.

### create_agent(opts)

Creates a new agent with configuration.

**Input**:
```elixir
opts :: [
  instructions: String.t(),
  tools: [atom()],
  agent_id: String.t() | nil,
  llm_config: map() | nil,
  stt_config: map() | nil,
  tts_config: map() | nil,
  vad_config: map() | nil,
  metadata: map() | nil
]
```

**Output**: `%LivekitexAgent.Agent{}`

**Errors**:
- `{:error, :invalid_instructions}` - Instructions empty or too long
- `{:error, :unknown_tool}` - Tool not registered in tool registry
- `{:error, :invalid_config}` - Provider configuration invalid

### start_session(agent, opts)

Starts a new agent session.

**Input**:
```elixir
agent :: %LivekitexAgent.Agent{}
opts :: [
  room_id: String.t() | nil,
  event_callbacks: map() | nil,
  user_data: map() | nil
]
```

**Output**: `{:ok, pid()} | {:error, term()}`

## LivekitexAgent.Agent

Agent configuration and lifecycle management.

### new(opts)

Creates agent struct with validation.

**Input**: Same as `LivekitexAgent.create_agent/1`

**Output**: `%LivekitexAgent.Agent{}`

### start_link(agent)

Starts agent as GenServer process.

**Input**: `agent :: %LivekitexAgent.Agent{}`

**Output**: `{:ok, pid()} | {:error, term()}`

### update_instructions(pid, instructions)

Updates agent instructions during runtime.

**Input**:
```elixir
pid :: pid()
instructions :: String.t()
```

**Output**: `:ok | {:error, term()}`

### add_tool(pid, tool)

Adds tool to agent's available tools.

**Input**:
```elixir
pid :: pid()
tool :: atom()
```

**Output**: `:ok | {:error, :tool_not_found}`

## LivekitexAgent.AgentSession

Session management and conversation handling.

### start_link(opts)

Starts new agent session.

**Input**:
```elixir
opts :: [
  agent: %LivekitexAgent.Agent{},
  room_id: String.t() | nil,
  event_callbacks: map() | nil,
  llm_client: pid() | nil,
  tts_client: pid() | nil,
  stt_client: pid() | nil,
  vad_client: pid() | nil,
  user_data: map() | nil
]
```

**Output**: `{:ok, pid()} | {:error, term()}`

### connect_to_room(session_pid, room_url, token)

Connects session to LiveKit room.

**Input**:
```elixir
session_pid :: pid()
room_url :: String.t()  # WebSocket URL
token :: String.t()     # JWT access token
```

**Output**: `{:ok, :connected} | {:error, term()}`

### process_text(session_pid, text)

Processes text input through agent pipeline.

**Input**:
```elixir
session_pid :: pid()
text :: String.t()
```

**Output**: `:ok`

### process_audio(session_pid, audio_data)

Processes audio input through STT and agent pipeline.

**Input**:
```elixir
session_pid :: pid()
audio_data :: binary()  # PCM16 audio data
```

**Output**: `:ok`

### get_conversation_state(session_pid)

Gets current conversation context.

**Input**: `session_pid :: pid()`

**Output**: `{:ok, map()} | {:error, term()}`

### get_metrics(session_pid)

Gets session performance metrics.

**Input**: `session_pid :: pid()`

**Output**:
```elixir
{:ok, %{
  messages_processed: non_neg_integer(),
  audio_segments_processed: non_neg_integer(),
  tool_calls_executed: non_neg_integer(),
  average_response_time_ms: float(),
  uptime_seconds: non_neg_integer()
}}
```

## LivekitexAgent.FunctionTool

Function tool registration and execution.

### register_tool(tool_definition)

Registers function tool in global registry.

**Input**:
```elixir
tool_definition :: %{
  name: String.t(),
  description: String.t(),
  module: atom(),
  function: atom(),
  arity: non_neg_integer(),
  parameters: [map()],
  return_type: String.t() | nil,
  timeout: pos_integer() | nil
}
```

**Output**: `:ok | {:error, term()}`

### execute_tool(tool_name, arguments, context)

Executes registered tool with arguments and context.

**Input**:
```elixir
tool_name :: String.t()
arguments :: map()
context :: %LivekitexAgent.RunContext{} | nil
```

**Output**: `{:ok, term()} | {:error, term()}`

### get_all_tools()

Gets all registered tools.

**Output**: `map()` - Map of tool name to tool definition

### to_openai_format(tools)

Converts tool definitions to OpenAI function calling format.

**Input**: `tools :: [map()]`

**Output**:
```elixir
[%{
  type: "function",
  function: %{
    name: String.t(),
    description: String.t(),
    parameters: %{
      type: "object",
      properties: map(),
      required: [String.t()]
    }
  }
}]
```

## LivekitexAgent.WorkerOptions

Worker configuration and management.

### new(opts)

Creates worker options configuration.

**Input**:
```elixir
opts :: [
  entry_point: function(),
  agent_name: String.t(),
  server_url: String.t(),
  api_key: String.t() | nil,
  api_secret: String.t() | nil,
  max_concurrent_jobs: pos_integer() | nil,
  worker_type: atom() | nil,
  region: String.t() | nil,
  drain_timeout: pos_integer() | nil,
  health_check_port: pos_integer() | nil
]
```

**Output**: `%LivekitexAgent.WorkerOptions{}`

### validate(worker_options)

Validates worker configuration.

**Input**: `worker_options :: %LivekitexAgent.WorkerOptions{}`

**Output**: `{:ok, %LivekitexAgent.WorkerOptions{}} | {:error, term()}`

### should_handle_job?(worker_options, job_request)

Determines if worker should accept job based on load and configuration.

**Input**:
```elixir
worker_options :: %LivekitexAgent.WorkerOptions{}
job_request :: map()
```

**Output**: `{:accept, :ok} | {:reject, String.t()}`

## LivekitexAgent.CLI

Command-line interface for worker management.

### main(args)

Main CLI entry point.

**Input**: `args :: [String.t()]`

**Output**: System exit with appropriate code

### start_worker(opts)

Starts worker in production mode.

**Input**: `opts :: map()`

**Output**: Does not return (runs indefinitely)

### start_dev_worker(opts)

Starts worker in development mode with hot-reload.

**Input**: `opts :: map()`

**Output**: Does not return (runs indefinitely)

## Error Handling Patterns

All APIs follow consistent error handling:

- **Validation errors**: `{:error, {:validation, field, reason}}`
- **Connection errors**: `{:error, {:connection, reason}}`
- **Timeout errors**: `{:error, {:timeout, operation}}`
- **External service errors**: `{:error, {:external, service, reason}}`
- **Resource errors**: `{:error, {:resource, type, reason}}`

## Type Specifications

All public functions include comprehensive `@spec` annotations for Dialyzer type checking. Key custom types:

```elixir
@type agent_id :: String.t()
@type session_id :: String.t()
@type tool_name :: String.t()
@type audio_data :: binary()
@type conversation_turn :: %{
  role: :user | :agent | :system,
  content: String.t(),
  timestamp: DateTime.t(),
  metadata: map()
}
```