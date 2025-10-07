defmodule LivekitexAgent.WorkerOptionsTest do
  use ExUnit.Case, async: true

  alias LivekitexAgent.WorkerOptions

  describe "from_config/1" do
    setup do
      # Clean state before each test
      Application.delete_env(:livekitex_agent, :default_worker_options)
      :ok
    end

    test "returns default configuration when no user config is provided" do
      # No user configuration
      Application.delete_env(:livekitex_agent, :default_worker_options)

      options = apply(WorkerOptions, :from_config, [])

      # Verify default values
      assert options.worker_pool_size == System.schedulers_online()
      assert options.agent_name == "elixir_agent"
      assert options.timeout == 300_000
      assert options.server_url == "ws://localhost:7880"
      assert options.api_key == ""
      assert options.api_secret == ""
      assert is_function(options.entry_point, 1)
      assert is_function(options.request_handler, 1)
    end

    test "merges user configuration with defaults" do
      # User provides partial configuration
      Application.put_env(:livekitex_agent, :default_worker_options, [
        worker_pool_size: 8,
        agent_name: "custom_agent",
        server_url: "ws://custom.livekit.cloud"
      ])

      options = apply(WorkerOptions, :from_config, [])

      # Verify user values are applied
      assert options.worker_pool_size == 8
      assert options.agent_name == "custom_agent"
      assert options.server_url == "ws://custom.livekit.cloud"

      # Verify defaults are still used for missing values
      assert options.timeout == 300_000
      assert options.api_key == ""
      assert is_function(options.entry_point, 1)
    end

    test "uses custom app_name when provided" do
      # Set config under different app name
      Application.put_env(:my_app, :default_worker_options, [
        worker_pool_size: 16,
        agent_name: "my_app_agent"
      ])

      options = apply(WorkerOptions, :from_config, [:my_app])

      assert options.worker_pool_size == 16
      assert options.agent_name == "my_app_agent"
      assert options.timeout == 300_000  # Default value
    end

    test "validates configuration and raises on invalid values" do
      # Invalid worker_pool_size
      Application.put_env(:livekitex_agent, :default_worker_options, [
        worker_pool_size: -1
      ])

      assert_raise ArgumentError, ~r/Invalid worker_pool_size.*Must be positive integer/, fn ->
        apply(WorkerOptions, :from_config, [])
      end
    end

    test "handles empty configuration gracefully" do
      # Empty config should work fine
      Application.put_env(:livekitex_agent, :default_worker_options, [])

      options = apply(WorkerOptions, :from_config, [])

      # Should get all defaults
      assert options.worker_pool_size == System.schedulers_online()
      assert options.agent_name == "elixir_agent"
      assert is_function(options.entry_point, 1)
    end
  end

  describe "with_defaults/1" do
    test "merges partial options with defaults" do
      partial_opts = [
        worker_pool_size: 4,
        agent_name: "test_agent"
      ]

      merged = apply(WorkerOptions, :with_defaults, [partial_opts])

      # Verify user values
      assert Keyword.get(merged, :worker_pool_size) == 4
      assert Keyword.get(merged, :agent_name) == "test_agent"

      # Verify defaults are applied
      assert Keyword.get(merged, :timeout) == 300_000
      assert Keyword.get(merged, :server_url) == "ws://localhost:7880"
      assert is_function(Keyword.get(merged, :entry_point), 1)
    end

    test "handles empty options list" do
      merged = apply(WorkerOptions, :with_defaults, [[]])

      # Should get all defaults
      assert Keyword.get(merged, :worker_pool_size) == System.schedulers_online()
      assert Keyword.get(merged, :agent_name) == "elixir_agent"
      assert Keyword.get(merged, :timeout) == 300_000
      assert is_function(Keyword.get(merged, :entry_point), 1)
    end

    test "preserves user values over defaults" do
      partial_opts = [
        worker_pool_size: 12,
        timeout: 600_000,
        agent_name: "override_agent",
        server_url: "wss://example.com"
      ]

      merged = apply(WorkerOptions, :with_defaults, [partial_opts])

      # User values should be preserved
      assert Keyword.get(merged, :worker_pool_size) == 12
      assert Keyword.get(merged, :timeout) == 600_000
      assert Keyword.get(merged, :agent_name) == "override_agent"
      assert Keyword.get(merged, :server_url) == "wss://example.com"

      # Defaults for unspecified values
      assert Keyword.get(merged, :api_key) == ""
      assert Keyword.get(merged, :api_secret) == ""
    end

    test "includes auto-generated entry_point by default" do
      merged = apply(WorkerOptions, :with_defaults, [[]])

      entry_point = Keyword.get(merged, :entry_point)
      assert is_function(entry_point, 1)

      # Verify it references the correct function
      # We can't directly compare function references, so just verify it's callable
      # The function should be the auto-generated entry point
    end

    test "includes sensible defaults for all enterprise features" do
      merged = apply(WorkerOptions, :with_defaults, [[]])

      # Enterprise features should have sensible defaults
      assert Keyword.get(merged, :load_balancer_strategy) == :load_based
      assert Keyword.get(merged, :job_queue_size) == 1000
      assert Keyword.get(merged, :auto_scaling_enabled) == false
      assert Keyword.get(merged, :min_workers) == 1
      assert Keyword.get(merged, :max_workers) == System.schedulers_online() * 4
      assert Keyword.get(merged, :cpu_threshold) == 0.8
      assert Keyword.get(merged, :memory_threshold) == 0.85
      assert Keyword.get(merged, :queue_threshold) == 0.9
      assert Keyword.get(merged, :backpressure_enabled) == true
    end
  end

  describe "validate!/1 error messages" do
    test "provides clear error for invalid worker_pool_size" do
      # Create with invalid worker_pool_size using apply to avoid compilation issues
      invalid_options = apply(WorkerOptions, :new, [[
        worker_pool_size: -1,
        entry_point: fn _ctx -> :ok end  # Dummy function for testing
      ]])

      assert_raise ArgumentError, ~r/Invalid worker_pool_size.*Must be positive integer.*Suggested: #{System.schedulers_online()}/, fn ->
        apply(WorkerOptions, :validate!, [invalid_options])
      end
    end

    test "provides clear error for invalid timeout" do
      invalid_options = apply(WorkerOptions, :new, [[
        timeout: -100,
        worker_pool_size: 4,
        entry_point: fn _ctx -> :ok end
      ]])

      assert_raise ArgumentError, ~r/Invalid timeout.*Must be positive integer.*Suggested: timeout: 300_000/, fn ->
        apply(WorkerOptions, :validate!, [invalid_options])
      end
    end

    test "provides clear error for invalid max_concurrent_jobs" do
      invalid_options = apply(WorkerOptions, :new, [[
        max_concurrent_jobs: 0,
        worker_pool_size: 4,
        timeout: 300_000,
        entry_point: fn _ctx -> :ok end
      ]])

      assert_raise ArgumentError, ~r/Invalid max_concurrent_jobs.*Must be positive integer.*Suggested: max_concurrent_jobs: 10/, fn ->
        apply(WorkerOptions, :validate!, [invalid_options])
      end
    end

    # T010: Enhanced error message scenarios
    test "error messages include problem description, impact, and fix instructions" do
      invalid_options = apply(WorkerOptions, :new, [[
        worker_pool_size: "not_a_number",
        entry_point: fn _ctx -> :ok end
      ]])

      exception = assert_raise ArgumentError, fn ->
        apply(WorkerOptions, :validate!, [invalid_options])
      end

      error_message = Exception.message(exception)

      # Verify error message structure: what, why, how-to-fix, suggested values
      assert error_message =~ ~r/Invalid worker_pool_size/  # What: problem description
      assert error_message =~ ~r/Must be positive integer/  # Why: validation requirement
      assert error_message =~ ~r/Suggested:/                # How-to-fix: specific guidance
      assert error_message =~ ~r/#{System.schedulers_online()}/  # Suggested values
    end

    test "error messages provide actionable guidance for string values" do
      invalid_options = apply(WorkerOptions, :new, [[
        worker_pool_size: 4,
        timeout: "5_minutes",
        entry_point: fn _ctx -> :ok end
      ]])

      exception = assert_raise ArgumentError, fn ->
        apply(WorkerOptions, :validate!, [invalid_options])
      end

      error_message = Exception.message(exception)

      # Should explain the specific problem and provide actionable fix
      assert error_message =~ ~r/Invalid timeout/
      assert error_message =~ ~r/received: "5_minutes"/i     # Shows received value
      assert error_message =~ ~r/timeout: \d+/               # Suggests numeric value
    end

    test "error messages explain impact on system functionality" do
      invalid_options = apply(WorkerOptions, :new, [[
        worker_pool_size: 0,
        entry_point: fn _ctx -> :ok end
      ]])

      exception = assert_raise ArgumentError, fn ->
        apply(WorkerOptions, :validate!, [invalid_options])
      end

      error_message = Exception.message(exception)

      # Should explain why this matters for the system
      assert error_message =~ ~r/worker pool.*cannot function/i or
             error_message =~ ~r/prevents.*worker.*creation/i or
             error_message =~ ~r/blocks.*job processing/i
    end

    test "error messages provide multiple fix suggestions for common mistakes" do
      invalid_options = apply(WorkerOptions, :new, [[
        worker_pool_size: -5,
        entry_point: fn _ctx -> :ok end
      ]])

      exception = assert_raise ArgumentError, fn ->
        apply(WorkerOptions, :validate!, [invalid_options])
      end

      error_message = Exception.message(exception)

      # Should provide multiple alternatives
      assert error_message =~ ~r/Suggested.*#{System.schedulers_online()}/  # Default suggestion
      assert error_message =~ ~r/or.*[48]|[48].*or/                         # Alternative values
    end

    test "error messages handle missing required fields" do
      invalid_options = apply(WorkerOptions, :new, [[
        worker_pool_size: 4
        # Missing entry_point
      ]])

      exception = assert_raise ArgumentError, fn ->
        apply(WorkerOptions, :validate!, [invalid_options])
      end

      error_message = Exception.message(exception)

      assert error_message =~ ~r/Missing.*entry_point/i
      assert error_message =~ ~r/fn.*ctx.*->.*end/         # Shows function syntax
      assert error_message =~ ~r/Required for.*agent/i     # Explains why needed
    end

    test "error messages provide context-specific suggestions" do
      # Test different invalid values get different suggestions
      test_cases = [
        {-1, ~r/positive.*integer.*Suggested.*#{System.schedulers_online()}/},
        {0, ~r/positive.*integer.*Suggested.*1.*or.*#{System.schedulers_online()}/},
        {1000, ~r/too high.*Suggested.*#{System.schedulers_online()}/}
      ]

      for {invalid_value, expected_pattern} <- test_cases do
        invalid_options = apply(WorkerOptions, :new, [[
          worker_pool_size: invalid_value,
          entry_point: fn _ctx -> :ok end
        ]])

        exception = assert_raise ArgumentError, fn ->
          apply(WorkerOptions, :validate!, [invalid_options])
        end

        error_message = Exception.message(exception)
        assert error_message =~ expected_pattern
      end
    end

    test "error messages are consistent in format across all validations" do
      # Test multiple different validation errors follow same format
      validation_tests = [
        {[worker_pool_size: -1], ~r/Invalid worker_pool_size:.+Must be.+Suggested:/},
        {[timeout: -100], ~r/Invalid timeout:.+Must be.+Suggested:/},
        {[max_concurrent_jobs: 0], ~r/Invalid max_concurrent_jobs:.+Must be.+Suggested:/}
      ]

      for {invalid_config, format_pattern} <- validation_tests do
        config_with_defaults = Keyword.merge([
          worker_pool_size: 4,
          timeout: 300_000,
          entry_point: fn _ctx -> :ok end
        ], invalid_config)

        invalid_options = apply(WorkerOptions, :new, [config_with_defaults])

        exception = assert_raise ArgumentError, fn ->
          apply(WorkerOptions, :validate!, [invalid_options])
        end

        error_message = Exception.message(exception)
        assert error_message =~ format_pattern,
               "Error message format inconsistent for #{inspect(invalid_config)}: #{error_message}"
      end
    end
  end
end
