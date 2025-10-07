# Data Model: Phoenix Integration Configuration Fix

**Date**: 7 de octubre de 2025
**Feature**: Fix Phoenix Integration Configuration Issue

## Entities

### WorkerOptions (Enhanced)

Configuration object that handles both explicit and default values for worker behavior.

**Fields:**
- `entry_point` (function): Entry point function (auto-generated if missing)
- `worker_pool_size` (pos_integer): Number of workers (defaults to System.schedulers_online())
- `request_handler` (function): Job request filter (defaults to accept-all)
- `job_executor_type` (atom): :process | :task | :genserver
- `timeout` (pos_integer): Job timeout in milliseconds
- `server_url` (string): LiveKit server URL
- `api_key` (string): LiveKit API key
- `api_secret` (string): LiveKit API secret
- `agent_name` (string): Agent identifier
- All other existing fields from current WorkerOptions struct

**New Methods:**
- `from_config/1`: Resolve configuration from Application environment
- `with_defaults/1`: Apply defaults to partial configuration
- `validate!/1`: Validate configuration with clear error messages

**Validation Rules:**
- `worker_pool_size` must be positive integer
- `timeout` must be positive integer
- `server_url` must be valid URL format
- `entry_point` must be callable function

**State Transitions:**
1. Raw config → Resolved config (via from_config/1)
2. Resolved config → Validated config (via validate!/1)
3. Validated config → WorkerOptions struct (via new/1)

### Application Configuration

Phoenix-style application environment configuration structure.

**Structure:**
```elixir
config :livekitex_agent,
  default_worker_options: [
    worker_pool_size: 4,
    timeout: 300_000,
    agent_name: "elixir_agent",
    server_url: "ws://localhost:7880",
    # other options...
  ]
```

**Fields:**
- `default_worker_options` (keyword list): User-provided configuration overrides
- Supports partial configuration (missing keys use hard-coded defaults)

**Relationships:**
- Read by `WorkerOptions.from_config/1`
- Merged with hard-coded defaults
- Validated before use

### Configuration Resolution Context

Internal data structure for tracking configuration sources and resolution.

**Fields:**
- `user_config` (keyword): From Application.get_env
- `defaults` (keyword): Hard-coded fallback values
- `resolved` (keyword): Merged final configuration
- `source_map` (map): Which source provided each value (for debugging)

**Methods:**
- `resolve/2`: Merge user config with defaults
- `trace_source/2`: Identify where each config value came from

## Data Flow

1. **Application Start**: Application.start/2 called by Phoenix
2. **Config Resolution**: WorkerOptions.from_config/1 reads app environment
3. **Default Merging**: Missing values filled from hard-coded defaults
4. **Validation**: WorkerOptions.validate!/1 checks all values
5. **Worker Initialization**: WorkerManager.start_link/1 receives valid WorkerOptions
6. **Pool Creation**: WorkerManager.initialize_worker_pool/1 accesses worker_pool_size safely

## Configuration Priority

1. **User Application Config** (highest priority)
2. **Library Default Config** (from config.exs)
3. **Hard-coded Defaults** (lowest priority)

This ensures users can override any setting while maintaining zero-config operation.

## Error Handling

- Invalid configuration values trigger clear error messages at startup
- Missing configuration keys are filled with documented defaults
- Configuration source is tracked for better debugging
- Validation failures prevent application startup with actionable errors