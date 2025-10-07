# Quickstart: Fix Phoenix Integration Configuration Error

**Feature**: 005-fix-phoenix-integration
**Date**: October 7, 2025
**Audience**: Developers implementing the fix

## Overview

This quickstart guide helps developers understand and implement the configuration error fix that prevents KeyError exceptions during Phoenix application startup when using livekitex_agent.

## Problem Summary

**Issue**: Phoenix applications crash on startup with `KeyError: key :worker_pool_size not found in: []`

**Root Cause**: `Application.resolve_worker_options/0` returns an empty list instead of a `WorkerOptions` struct

**Impact**: Prevents Phoenix applications from starting when livekitex_agent is included as a dependency

## Solution Architecture

### Three-Layer Fix Approach

1. **Input Validation**: Add type checking in WorkerManager
2. **Configuration Robustness**: Enhance error handling in Application module
3. **Graceful Fallback**: Provide emergency defaults when configuration fails

```
User Config (config.exs)
    ↓ (with validation)
Application.resolve_worker_options/0
    ↓ (with error handling)
WorkerOptions struct
    ↓ (with type checking)
WorkerManager.start_link/1
    ↓
Successful Application Startup
```

## Implementation Steps

### Step 1: Fix Application.resolve_worker_options/0

**File**: `lib/livekitex_agent/application.ex`

**Current Issue**:
```elixir
defp resolve_worker_options do
  apply(LivekitexAgent.WorkerOptions, :from_config, [])
  # Can throw exceptions, returns wrong type on failure
end
```

**Fixed Implementation**:
```elixir
defp resolve_worker_options do
  try do
    # Ensure we get a keyword list from config
    user_config = Application.get_env(:livekitex_agent, :default_worker_options, [])

    config = case user_config do
      list when is_list(list) -> list
      _ -> []
    end

    LivekitexAgent.WorkerOptions.from_config(config)
  rescue
    error ->
      Logger.error("""
      Failed to resolve WorkerOptions configuration: #{inspect(error)}

      This error occurs when livekitex_agent cannot initialize properly.
      To fix this:
      1. Ensure your config.exs has proper configuration
      2. Check that all required dependencies are available
      3. Verify your entry_point function is valid

      Falling back to emergency defaults...
      """)

      create_emergency_fallback()
  end
end

defp create_emergency_fallback do
  LivekitexAgent.WorkerOptions.new([
    entry_point: fn _ctx -> :ok end,
    worker_pool_size: System.schedulers_online(),
    agent_name: "emergency_fallback_agent",
    timeout: 300_000,
    max_concurrent_jobs: 1
  ])
end
```

### Step 2: Add Input Validation to WorkerManager

**File**: `lib/livekitex_agent/worker_manager.ex`

**Add at beginning of init/1**:
```elixir
def init(worker_options) do
  # Validate input type
  validated_options = validate_worker_options_input(worker_options)

  # ... rest of existing init logic
end

defp validate_worker_options_input(%LivekitexAgent.WorkerOptions{} = opts), do: opts
defp validate_worker_options_input(invalid) do
  raise ArgumentError, """
  WorkerManager requires a WorkerOptions struct, got: #{inspect(invalid)}

  This usually indicates a configuration resolution issue.
  Expected: %LivekitexAgent.WorkerOptions{}
  Received: #{inspect(invalid)}

  Check your Phoenix application configuration or contact support.
  """
end
```

### Step 3: Enhance WorkerOptions.from_config/1 Error Handling

**File**: `lib/livekitex_agent/worker_options.ex`

**Update from_config/1 function**:
```elixir
def from_config(app_name \\ :livekitex_agent) do
  try do
    user_config = Application.get_env(app_name, :default_worker_options, [])

    # Ensure we have a valid keyword list
    config = case user_config do
      list when is_list(list) -> list
      nil -> []
      _ ->
        Logger.warning("Invalid configuration format for :default_worker_options, using defaults")
        []
    end

    config
    |> with_defaults()
    |> new()
    |> validate!()
  rescue
    error ->
      Logger.error("WorkerOptions.from_config failed: #{inspect(error)}")
      reraise error, __STACKTRACE__
  end
end
```

## Testing Strategy

### Unit Tests

**File**: `test/application_test.exs`

```elixir
defmodule LivekitexAgent.ApplicationTest do
  use ExUnit.Case

  describe "resolve_worker_options/0" do
    test "handles empty configuration" do
      Application.put_env(:livekitex_agent, :default_worker_options, [])
      opts = LivekitexAgent.Application.resolve_worker_options()
      assert %LivekitexAgent.WorkerOptions{} = opts
      assert opts.worker_pool_size > 0
    end

    test "handles nil configuration" do
      Application.put_env(:livekitex_agent, :default_worker_options, nil)
      opts = LivekitexAgent.Application.resolve_worker_options()
      assert %LivekitexAgent.WorkerOptions{} = opts
    end

    test "handles invalid configuration type" do
      Application.put_env(:livekitex_agent, :default_worker_options, "invalid")
      opts = LivekitexAgent.Application.resolve_worker_options()
      assert %LivekitexAgent.WorkerOptions{} = opts
    end
  end
end
```

**File**: `test/worker_manager_test.exs`

```elixir
defmodule LivekitexAgent.WorkerManagerTest do
  use ExUnit.Case

  describe "init/1 input validation" do
    test "accepts valid WorkerOptions struct" do
      opts = LivekitexAgent.WorkerOptions.new([
        entry_point: fn _ -> :ok end,
        worker_pool_size: 2
      ])

      assert {:ok, _state} = LivekitexAgent.WorkerManager.init(opts)
    end

    test "rejects empty list with clear error" do
      assert_raise ArgumentError, ~r/WorkerManager requires a WorkerOptions struct/, fn ->
        LivekitexAgent.WorkerManager.init([])
      end
    end

    test "rejects nil with clear error" do
      assert_raise ArgumentError, ~r/WorkerManager requires a WorkerOptions struct/, fn ->
        LivekitexAgent.WorkerManager.init(nil)
      end
    end
  end
end
```

### Integration Tests

**File**: `test/phoenix_integration_test.exs`

```elixir
defmodule LivekitexAgent.PhoenixIntegrationTest do
  use ExUnit.Case

  test "application starts successfully with default config" do
    # Simulate Phoenix application startup
    {:ok, _pid} = LivekitexAgent.Application.start(:normal, [])

    # Verify WorkerManager is running
    assert Process.whereis(LivekitexAgent.WorkerManager)
  end

  test "application starts with fallback when config fails" do
    # Simulate configuration failure
    original_config = Application.get_env(:livekitex_agent, :default_worker_options)
    Application.put_env(:livekitex_agent, :default_worker_options, :invalid)

    try do
      {:ok, _pid} = LivekitexAgent.Application.start(:normal, [])
      assert Process.whereis(LivekitexAgent.WorkerManager)
    after
      Application.put_env(:livekitex_agent, :default_worker_options, original_config)
    end
  end
end
```

## Verification Steps

### Manual Testing

1. **Test Normal Configuration**:
   ```elixir
   # In iex
   opts = LivekitexAgent.WorkerOptions.from_config()
   LivekitexAgent.WorkerManager.start_link(opts)
   ```

2. **Test Empty Configuration**:
   ```elixir
   Application.put_env(:livekitex_agent, :default_worker_options, [])
   opts = LivekitexAgent.Application.resolve_worker_options()
   IO.inspect(opts) # Should be valid WorkerOptions struct
   ```

3. **Test Phoenix Integration**:
   ```bash
   # In Phoenix application with livekitex_agent dependency
   mix phx.server
   # Should start without KeyError
   ```

### Regression Testing

Run existing test suite to ensure no breaking changes:
```bash
mix test
mix credo --strict
mix dialyzer
```

## Deployment Checklist

- [ ] All unit tests pass
- [ ] Integration tests pass
- [ ] Manual verification completed
- [ ] Credo static analysis passes
- [ ] Dialyzer type checking passes
- [ ] Documentation updated
- [ ] Error messages are clear and actionable
- [ ] Fallback behavior works correctly
- [ ] Performance requirements met (< 100ms config resolution)

## Troubleshooting

### Common Issues

**Issue**: Tests fail with supervision tree errors
**Solution**: Ensure test setup properly manages application lifecycle

**Issue**: Dialyzer warnings about spec mismatches
**Solution**: Update function specs to reflect new error handling

**Issue**: Configuration still not working in Phoenix
**Solution**: Check that emergency fallback is being triggered and logged

### Debug Commands

```elixir
# Check current configuration
Application.get_env(:livekitex_agent, :default_worker_options)

# Test WorkerOptions creation
LivekitexAgent.WorkerOptions.from_config()

# Test application startup
LivekitexAgent.Application.start(:normal, [])

# Check running processes
Process.whereis(LivekitexAgent.WorkerManager)
```

## Next Steps

After implementing this fix:

1. Monitor error logs for configuration issues in production
2. Consider adding telemetry for configuration resolution metrics
3. Evaluate need for configuration validation at compile time
4. Review other similar error patterns in the codebase

## Support

If issues persist after implementing this fix:

1. Check application logs for specific error messages
2. Verify Phoenix application configuration
3. Test with minimal reproduction case
4. File issue with specific error details and steps to reproduce