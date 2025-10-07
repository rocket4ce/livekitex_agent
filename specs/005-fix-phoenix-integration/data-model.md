# Data Model: Fix Phoenix Integration Configuration Error

**Feature**: 005-fix-phoenix-integration
**Date**: October 7, 2025
**Source**: Extracted from [spec.md](./spec.md)

## Core Entities

### WorkerOptions

**Purpose**: Configuration structure that defines how worker processes should be initialized and managed.

**Attributes**:
- `worker_pool_size`: Positive integer defining number of worker processes (required)
- `timeout`: Integer in milliseconds for job execution timeout
- `entry_point`: Function reference for job handling logic
- `agent_name`: String identifier for the agent instance
- `server_url`: String URL for LiveKit server connection
- `api_key`: String for LiveKit authentication
- `api_secret`: String for LiveKit authentication
- `max_concurrent_jobs`: Integer limit for concurrent job execution
- `health_check_port`: Integer port number for health monitoring
- `load_threshold`: Float between 0.0-1.0 for load balancing
- `graceful_shutdown_timeout`: Integer milliseconds for shutdown grace period

**Validation Rules**:
- `worker_pool_size` must be positive integer > 0
- `timeout` must be positive integer > 0
- `entry_point` must be valid function reference or nil
- `server_url` must be valid WebSocket URL format
- `max_concurrent_jobs` must be positive integer
- `health_check_port` must be valid port number (1-65535)
- `load_threshold` must be float between 0.0 and 1.0

**State Transitions**:
- Draft → Validated (via `WorkerOptions.validate!/1`)
- Validated → Active (when passed to WorkerManager)

**Relationships**:
- Used by `WorkerManager` for initialization
- Created by `Application.resolve_worker_options/0`
- Configured via `Application` environment

### Application Configuration

**Purpose**: Environment-based settings that customize agent behavior for different deployment contexts.

**Attributes**:
- `:default_worker_options`: Keyword list of WorkerOptions field overrides
- `:tool_registry`: Configuration for tool discovery and management
- `:media`: Configuration for audio/video processing defaults
- `:session`: Configuration for session management defaults

**Validation Rules**:
- `:default_worker_options` must be keyword list or nil
- Nested configurations must match expected schemas
- Values must be compatible with WorkerOptions field types

**Relationships**:
- Source for `WorkerOptions` field values
- Read by `Application.resolve_worker_options/0`
- Set via `config.exs` files

### Error Context

**Purpose**: Structured information about configuration failures to aid debugging.

**Attributes**:
- `error_type`: Atom describing error category (:invalid_config, :missing_field, :type_error)
- `failed_field`: String name of problematic configuration field
- `received_value`: Any - the actual value that caused the error
- `expected_type`: String description of expected value format
- `suggestion`: String with actionable fix recommendation
- `fallback_applied`: Boolean indicating if emergency defaults were used

**Validation Rules**:
- `error_type` must be one of predefined error categories
- `suggestion` must be non-empty actionable guidance
- `fallback_applied` must be boolean

**State Transitions**:
- Created → Logged (error information recorded)
- Logged → Resolved (user fixes configuration)

## Data Flow

### Configuration Resolution Flow

```
config.exs settings
  ↓ (Application.get_env/3)
Application Configuration
  ↓ (WorkerOptions.from_config/1)
WorkerOptions (draft)
  ↓ (WorkerOptions.validate!/1)
WorkerOptions (validated)
  ↓ (WorkerManager.start_link/1)
Active Worker Pool
```

### Error Handling Flow

```
Configuration Resolution Attempt
  ↓ (exception occurs)
Error Context Creation
  ↓ (logging + fallback creation)
Emergency WorkerOptions
  ↓ (continue startup)
Degraded Mode Operation
```

## Persistence Strategy

### Configuration Storage
- **Primary**: Elixir Application environment (runtime only)
- **Source**: config.exs files (compile-time defaults)
- **Override**: System environment variables (deployment-specific)

### Error Tracking
- **Storage**: Application logs (structured logging)
- **Retention**: Follow standard log rotation policies
- **Format**: JSON-structured for parsing and monitoring

### State Management
- **WorkerOptions**: Immutable once validated, stored in GenServer state
- **Error Context**: Ephemeral, exists only during error handling
- **Configuration**: Cached in Application environment, read-only after startup

## Constraints

### Performance Requirements
- Configuration resolution must complete within 100ms
- WorkerOptions validation should be sub-millisecond
- Error context creation should not impact startup time

### Compatibility Requirements
- Must support all existing WorkerOptions fields
- Backward compatible with current config.exs format
- No breaking changes to public APIs

### Reliability Requirements
- Configuration failures must not prevent application startup
- Error messages must provide actionable guidance
- Fallback configuration must enable basic functionality

## Future Considerations

### Extensibility
- New WorkerOptions fields should follow existing patterns
- Error context can be extended with additional debugging info
- Configuration validation can be enhanced without breaking changes

### Monitoring Integration
- Configuration resolution metrics for observability
- Error frequency tracking for reliability monitoring
- Performance telemetry for startup optimization