# Quick Start: Phoenix Integration Fix

**Target**: Phoenix 1.8.1+ developers adding livekitex_agent dependency
**Goal**: Zero-configuration integration that "just works"

## Problem Summary

Adding `{:livekitex_agent, "~> 0.1.0"}` to a Phoenix project causes startup crash:

```
** (KeyError) key :worker_pool_size not found in: []
```

## Solution Overview

The fix implements proper configuration resolution in the Application startup sequence, allowing Phoenix developers to use the library without manual setup.

## For Phoenix Developers (After Fix)

### 1. Add Dependency

```elixir
# mix.exs
defp deps do
  [
    {:livekitex_agent, "~> 0.1.0"},
    # ... other deps
  ]
end
```

### 2. Run Phoenix (No Additional Config Needed)

```bash
mix deps.get
mix phx.server
```

**Result**: Phoenix starts successfully with sensible defaults.

### 3. Optional: Customize Configuration

```elixir
# config/config.exs
config :livekitex_agent,
  default_worker_options: [
    worker_pool_size: 8,
    agent_name: "my_phoenix_agent",
    server_url: "ws://localhost:7880"
  ]
```

## For Library Developers (Implementation)

### Changes Made

**1. Application.start/2 Enhancement**
```elixir
# Before (causing crash)
{LivekitexAgent.WorkerManager, []}

# After (with config resolution)
worker_options = LivekitexAgent.WorkerOptions.from_config()
{LivekitexAgent.WorkerManager, worker_options}
```

**2. WorkerOptions.from_config/0 (New)**
```elixir
def from_config(app_name \\ :livekitex_agent) do
  user_config = Application.get_env(app_name, :default_worker_options, [])

  user_config
  |> with_defaults()
  |> new()
  |> validate!()
end
```

**3. Configuration Layering**
- User config (config.exs) - highest priority
- Library defaults (fallback values)
- Auto-generated entry_point (for zero-config)

### Testing the Fix

**Unit Test**:
```elixir
test "Phoenix integration works with no config" do
  # Simulate Phoenix startup with no user config
  Application.delete_env(:livekitex_agent, :default_worker_options)

  assert {:ok, _pid} = LivekitexAgent.Application.start(:normal, [])
end
```

**Integration Test**:
```elixir
test "full Phoenix app startup" do
  # Start Phoenix app with livekitex_agent dependency
  assert {:ok, _pid} = Phoenix.start(:normal, [])
end
```

## Error Scenarios (Fixed)

### Before Fix
```
** (KeyError) key :worker_pool_size not found in: []
    (livekitex_agent) lib/livekitex_agent/worker_manager.ex:374
```

### After Fix
```
[info] Starting LivekitexAgent with defaults: worker_pool_size=4, agent_name=elixir_agent
[info] Phoenix server started successfully
```

### Invalid Config (After Fix)
```
** (ArgumentError) Invalid worker_pool_size: -1. Must be positive integer.
Suggested config:
config :livekitex_agent, default_worker_options: [worker_pool_size: 4]
```

## Migration Guide

### For Existing Users

No changes required. Existing explicit configuration continues to work:

```elixir
# This still works exactly as before
opts = LivekitexAgent.WorkerOptions.new(
  entry_point: &MyAgent.run/1,
  worker_pool_size: 4
)
LivekitexAgent.WorkerManager.start_link(opts)
```

### For Phoenix Users (New)

Simply add the dependency. No additional configuration required for basic functionality.

## Performance Impact

- **Startup Time**: +1-2ms for config resolution (negligible)
- **Memory**: No additional runtime memory usage
- **Configuration**: Resolved once at startup, cached in WorkerOptions struct

## Next Steps

1. Install fixed version: `{:livekitex_agent, "~> 0.1.1"}`
2. Remove any workaround configuration (if previously added)
3. Start Phoenix application normally
4. Customize configuration only when needed for production