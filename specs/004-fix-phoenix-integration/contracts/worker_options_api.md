# API Contract: WorkerOptions Configuration

**Module**: `LivekitexAgent.WorkerOptions`
**Purpose**: Configuration resolution and validation for Phoenix integration

## Public API

### `from_config(app_name \\ :livekitex_agent) :: WorkerOptions.t()`

Resolves configuration from Application environment with fallback defaults.

**Parameters:**
- `app_name` (atom): Application name to read config from

**Returns:**
- `WorkerOptions.t()`: Fully resolved and validated configuration

**Behavior:**
1. Read `Application.get_env(app_name, :default_worker_options, [])`
2. Merge with hard-coded defaults (user config takes priority)
3. Generate auto entry_point if missing
4. Validate all values
5. Return WorkerOptions struct

**Errors:**
- Raises `ArgumentError` with clear message for invalid config values
- Provides suggested fixes in error messages

**Example:**
```elixir
# With user config in config.exs
config :livekitex_agent, default_worker_options: [worker_pool_size: 8]

# Usage
opts = WorkerOptions.from_config()
# => %WorkerOptions{worker_pool_size: 8, entry_point: &auto_generated/1, ...}
```

### `validate!(opts) :: WorkerOptions.t()`

Validates WorkerOptions configuration and raises on errors.

**Parameters:**
- `opts` (WorkerOptions.t()): Configuration to validate

**Returns:**
- `WorkerOptions.t()`: Same struct if valid

**Errors:**
- `ArgumentError` for invalid worker_pool_size (must be positive)
- `ArgumentError` for invalid timeout (must be positive)
- `ArgumentError` for invalid server_url (must be valid URL)
- `ArgumentError` for invalid entry_point (must be function)

### `with_defaults(partial_opts) :: keyword()`

Merges partial configuration with hard-coded defaults.

**Parameters:**
- `partial_opts` (keyword): User-provided configuration

**Returns:**
- `keyword()`: Complete configuration with defaults applied

**Example:**
```elixir
WorkerOptions.with_defaults([worker_pool_size: 4])
# => [worker_pool_size: 4, timeout: 300_000, entry_point: &auto_entry_point/1, ...]
```

## Module Contract: Application

### `start(_type, _args) :: {:ok, pid()} | {:error, term()}`

Enhanced application startup with configuration resolution.

**Behavior:**
1. Resolve WorkerOptions using `WorkerOptions.from_config/0`
2. Start supervision tree with resolved configuration
3. Pass WorkerOptions struct to WorkerManager instead of empty list

**Error Handling:**
- Clear error messages for configuration issues
- Suggests fixes for common problems (missing worker_pool_size, etc.)

## Module Contract: WorkerManager

### `start_link(worker_options) :: {:ok, pid()} | {:error, term()}`

Starts WorkerManager with properly initialized WorkerOptions.

**Parameters:**
- `worker_options` (WorkerOptions.t()): Validated configuration struct

**Behavior:**
- Expects WorkerOptions struct, not keyword list or empty list
- Uses `worker_options.worker_pool_size` safely (no KeyError possible)
- Initializes worker pool based on resolved configuration

## Configuration Schema

### Application Environment

```elixir
config :livekitex_agent,
  default_worker_options: [
    # Core worker settings
    worker_pool_size: pos_integer(),           # Default: System.schedulers_online()
    timeout: pos_integer(),                    # Default: 300_000 (5 minutes)

    # LiveKit connection
    server_url: String.t(),                    # Default: "ws://localhost:7880"
    api_key: String.t(),                       # Default: ""
    api_secret: String.t(),                    # Default: ""

    # Agent configuration
    agent_name: String.t(),                    # Default: "elixir_agent"
    worker_type: atom(),                       # Default: :voice_agent

    # Advanced options (all have sensible defaults)
    max_concurrent_jobs: pos_integer(),        # Default: 10
    health_check_interval: pos_integer(),      # Default: 30_000
    # ... other WorkerOptions fields
  ]
```

### Hard-coded Defaults

All fields from `WorkerOptions.new/1` have hard-coded defaults to ensure zero-config operation when no user configuration is provided.

## Error Messages

### Configuration Validation Errors

```elixir
# Invalid worker_pool_size
"Invalid worker_pool_size: -1. Must be positive integer. Suggested: 4"

# Missing configuration (informational)
"No configuration found for :livekitex_agent. Using defaults.
To customize, add to config.exs:
config :livekitex_agent, default_worker_options: [worker_pool_size: 4]"
```

## Backward Compatibility

- Existing explicit WorkerOptions.new/1 usage continues to work unchanged
- New from_config/0 method provides Phoenix integration path
- No breaking changes to existing API surface