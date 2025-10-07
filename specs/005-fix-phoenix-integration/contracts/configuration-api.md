# Internal API Contracts: Configuration Management

**Feature**: 005-fix-phoenix-integration
**Date**: October 7, 2025
**Type**: Internal Library APIs

## WorkerOptions Module Contract

### `WorkerOptions.from_config/1`

**Function Signature**:
```elixir
@spec from_config(keyword()) :: WorkerOptions.t() | no_return()
```

**Input Contract**:
```elixir
# Valid inputs
config = [
  worker_pool_size: pos_integer(),
  timeout: pos_integer(),
  entry_point: (any() -> any()) | nil,
  agent_name: String.t(),
  # ... other optional fields
]

# Edge cases that must be handled
config = []                    # Empty list -> use all defaults
config = nil                   # Should be converted to []
config = "invalid"             # Should raise clear ArgumentError
```

**Output Contract**:
```elixir
# Success case
%WorkerOptions{
  worker_pool_size: pos_integer(),
  timeout: pos_integer(),
  entry_point: function(),
  # ... all fields populated with defaults or user values
}

# Error case
raise ArgumentError, "Clear message with fix suggestions"
```

**Error Scenarios**:
- Invalid configuration type (not keyword list) → `ArgumentError`
- Invalid field values (negative numbers, etc.) → `ArgumentError`
- Missing required dependencies → `RuntimeError`

### `WorkerOptions.validate!/1`

**Function Signature**:
```elixir
@spec validate!(WorkerOptions.t()) :: WorkerOptions.t() | no_return()
```

**Input Contract**:
```elixir
%WorkerOptions{
  # Any WorkerOptions struct, potentially with invalid values
}
```

**Output Contract**:
```elixir
# Success: Returns same struct unchanged
%WorkerOptions{} = validated_options

# Error: Raises with specific field and suggestion
raise ArgumentError, "Invalid worker_pool_size: -1. Must be positive integer. Suggested: 4"
```

## Application Module Contract

### `Application.resolve_worker_options/0`

**Function Signature**:
```elixir
@spec resolve_worker_options() :: WorkerOptions.t()
```

**Input Contract**: None (reads from Application environment)

**Output Contract**:
```elixir
# Always returns valid WorkerOptions struct
%WorkerOptions{
  worker_pool_size: pos_integer(),
  # ... all fields properly initialized
}

# Never raises - uses fallback on any error
```

**Behavior Contract**:
1. **Primary**: Read `:livekitex_agent, :default_worker_options`
2. **Fallback**: Create emergency defaults on any error
3. **Logging**: Log errors with actionable guidance
4. **Performance**: Complete within 100ms

**Error Handling Contract**:
- Configuration read fails → Log error + use emergency defaults
- WorkerOptions creation fails → Log error + use emergency defaults
- Validation fails → Log error + use emergency defaults
- **Never** raises exceptions or returns invalid data

## WorkerManager Module Contract

### `WorkerManager.start_link/1`

**Function Signature**:
```elixir
@spec start_link(WorkerOptions.t()) :: GenServer.on_start()
```

**Input Contract**:
```elixir
# Must receive valid WorkerOptions struct
%WorkerOptions{
  worker_pool_size: pos_integer(),
  # ... all required fields present
}

# Invalid inputs should raise clear errors
invalid_input = []            # Empty list
invalid_input = nil           # Nil value
invalid_input = %{some: :map} # Wrong type
```

**Output Contract**:
```elixir
# Success cases
{:ok, pid()}                  # Normal startup
{:error, {:already_started, pid()}} # Already running

# Error cases with clear messages
{:error, {:shutdown, reason}} when reason includes configuration context
```

**Behavior Contract**:
1. **Validation**: Verify input is WorkerOptions struct
2. **Initialization**: Create worker pool based on configuration
3. **Error Handling**: Provide clear error messages for debugging
4. **Performance**: Initialize worker pool within 1 second

### `WorkerManager.initialize_worker_pool/1` (private)

**Function Signature**:
```elixir
@spec initialize_worker_pool(WorkerOptions.t()) :: %{String.t() => worker_info()}
```

**Input Contract**:
```elixir
# Must receive WorkerOptions struct with valid worker_pool_size
%WorkerOptions{worker_pool_size: count} when is_integer(count) and count > 0
```

**Output Contract**:
```elixir
# Map of worker_id => worker_info
%{
  "worker_1_abc123" => %{
    id: String.t(),
    started_at: DateTime.t(),
    job_count: non_neg_integer(),
    last_job_at: DateTime.t() | nil
  }
}
```

**Error Contract**:
- Invalid input type → Raise `ArgumentError` with clear message
- Zero/negative pool size → Raise `ArgumentError` with suggestion

## Configuration Schema Contract

### Application Environment Schema

**Expected Structure**:
```elixir
config :livekitex_agent,
  default_worker_options: [
    worker_pool_size: pos_integer(),      # Optional, defaults to System.schedulers_online()
    timeout: pos_integer(),               # Optional, defaults to 300_000
    entry_point: (any() -> any()),        # Optional, defaults to auto-generated
    agent_name: String.t(),               # Optional, defaults to "elixir_agent"
    server_url: String.t(),               # Optional, defaults to "ws://localhost:7880"
    api_key: String.t(),                  # Optional, defaults to ""
    api_secret: String.t(),               # Optional, defaults to ""
    max_concurrent_jobs: pos_integer(),   # Optional, defaults to 10
    health_check_port: pos_integer()      # Optional, defaults to 8080
  ]
```

**Validation Rules**:
- All fields are optional (library provides defaults)
- Values must match expected types when provided
- Invalid values should be caught by WorkerOptions validation

## Error Message Standards

### Format Requirements

All error messages must include:
1. **What went wrong**: Clear description of the problem
2. **Why it matters**: Context about the impact
3. **How to fix**: Specific actionable steps
4. **Fallback status**: Whether emergency defaults are active

**Example Error Format**:
```
Failed to resolve WorkerOptions configuration: %KeyError{key: :worker_pool_size}

This error occurs when livekitex_agent cannot initialize properly.
To fix this:
1. Ensure your config.exs has proper configuration
2. Check that all required dependencies are available
3. Verify your entry_point function is valid

Falling back to emergency defaults (worker_pool_size: 4)...
Application will start with basic functionality.
```

## Performance Contracts

### Timing Requirements
- `resolve_worker_options/0`: < 100ms
- `WorkerOptions.validate!/1`: < 1ms
- `WorkerManager.start_link/1`: < 1000ms
- `initialize_worker_pool/1`: < 500ms

### Resource Usage
- Memory overhead: < 1MB for configuration handling
- CPU usage: < 5% during configuration resolution
- No persistent storage required for configuration

## Backward Compatibility

### Guaranteed Interfaces
- Existing `WorkerOptions` struct fields remain unchanged
- Current `config.exs` format continues to work
- Public API signatures remain stable

### Migration Path
- No migration required - fixes are internal improvements
- Enhanced error messages improve developer experience
- Fallback behavior maintains application stability