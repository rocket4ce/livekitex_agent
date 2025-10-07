defmodule LivekitexAgent.ApplicationTest do
  @moduledoc """
  Comprehensive test cases for Application.resolve_worker_options/0
  covering all edge cases from contracts/configuration-api.md.

  Tests ensure robust configuration resolution without crashes
  and proper fallback behavior for Phoenix integration startup.
  """

  use ExUnit.Case, async: false
  alias LivekitexAgent.{WorkerOptions, TestFactories}
  import ExUnit.CaptureLog
  require Logger

  # Access to private resolve_worker_options function for testing
  defp call_resolve_worker_options do
    # Use reflection to call the private function
    :erlang.apply(LivekitexAgent.Application, :resolve_worker_options, [])
  end

  describe "resolve_worker_options/0" do
    setup do
      # Store original configuration
      original_config = Application.get_env(:livekitex_agent, :default_worker_options)

      on_exit(fn ->
        # Restore original configuration
        if original_config do
          Application.put_env(:livekitex_agent, :default_worker_options, original_config)
        else
          Application.delete_env(:livekitex_agent, :default_worker_options)
        end
      end)

      :ok
    end

    test "returns valid WorkerOptions with complete configuration" do
      # Setup valid configuration
      valid_config = TestFactories.valid_worker_config()
      Application.put_env(:livekitex_agent, :default_worker_options, valid_config)

      result = call_resolve_worker_options()

      assert %WorkerOptions{} = result
      assert result.worker_pool_size == valid_config[:worker_pool_size]
      assert result.timeout == valid_config[:timeout]
      assert result.agent_name == valid_config[:agent_name]
      assert result.server_url == valid_config[:server_url]
      assert result.max_concurrent_jobs == valid_config[:max_concurrent_jobs]
    end

    test "returns valid WorkerOptions with minimal configuration" do
      # Setup minimal valid configuration
      minimal_config = TestFactories.minimal_worker_config()
      Application.put_env(:livekitex_agent, :default_worker_options, minimal_config)

      result = call_resolve_worker_options()

      assert %WorkerOptions{} = result
      assert result.worker_pool_size == minimal_config[:worker_pool_size]
      assert result.timeout == minimal_config[:timeout]
      # Should have defaults for missing fields
      assert is_binary(result.agent_name)
      assert is_binary(result.server_url)
    end

    test "handles empty configuration gracefully" do
      # Setup empty configuration (should use all defaults)
      Application.put_env(:livekitex_agent, :default_worker_options, [])

      result = call_resolve_worker_options()

      assert %WorkerOptions{} = result
      assert result.worker_pool_size > 0
      assert result.timeout > 0
      assert is_binary(result.agent_name)
      assert is_binary(result.server_url)
    end

    test "handles nil configuration by using defaults" do
      # Setup nil configuration
      Application.put_env(:livekitex_agent, :default_worker_options, nil)

      result = call_resolve_worker_options()

      assert %WorkerOptions{} = result
      assert result.worker_pool_size > 0
      assert result.timeout > 0
    end

    test "handles missing configuration key by using defaults" do
      # Remove configuration entirely
      Application.delete_env(:livekitex_agent, :default_worker_options)

      result = call_resolve_worker_options()

      assert %WorkerOptions{} = result
      assert result.worker_pool_size > 0
      assert result.timeout > 0
    end

    test "falls back to emergency configuration on invalid config type" do
      # Setup invalid configuration (string instead of keyword list)
      Application.put_env(:livekitex_agent, :default_worker_options, "invalid_config")

      log_output = capture_log(fn ->
        result = call_resolve_worker_options()
        assert %WorkerOptions{} = result
        assert result.worker_pool_size > 0
        assert result.agent_name == "emergency_fallback_agent"
      end)

      assert log_output =~ "Failed to resolve WorkerOptions configuration"
      assert log_output =~ "Falling back to minimal configuration"
    end

    test "falls back to emergency configuration on invalid field values" do
      # Setup configuration with invalid field values
      invalid_configs = TestFactories.invalid_worker_configs()
      invalid_config = invalid_configs.negative_worker_pool_size
      Application.put_env(:livekitex_agent, :default_worker_options, invalid_config)

      log_output = capture_log(fn ->
        result = call_resolve_worker_options()
        assert %WorkerOptions{} = result
        assert result.worker_pool_size > 0  # Should use emergency fallback
        assert result.agent_name == "emergency_fallback_agent"
      end)

      assert log_output =~ "Failed to resolve WorkerOptions configuration"
    end

    test "falls back to emergency configuration on validation failure" do
      # Setup configuration that passes initial creation but fails validation
      config_with_validation_issue = [
        worker_pool_size: 4,
        timeout: 300_000,
        entry_point: "not_a_function",  # Will cause validation error
        agent_name: "test_agent"
      ]
      Application.put_env(:livekitex_agent, :default_worker_options, config_with_validation_issue)

      log_output = capture_log(fn ->
        result = call_resolve_worker_options()
        assert %WorkerOptions{} = result
        # Should have emergency fallback values
        assert result.worker_pool_size == System.schedulers_online()
        assert result.agent_name == "emergency_fallback_agent"
      end)

      assert log_output =~ "Failed to resolve WorkerOptions configuration"
    end

    test "emergency fallback creates valid configuration that passes validation" do
      # Force an error to trigger emergency fallback
      Application.put_env(:livekitex_agent, :default_worker_options, %{invalid: :map})

      capture_log(fn ->
        result = call_resolve_worker_options()

        # Emergency fallback should always create valid WorkerOptions
        assert %WorkerOptions{} = result
        assert result.worker_pool_size > 0
        assert is_function(result.entry_point, 1)
        assert result.agent_name == "emergency_fallback_agent"

        # Should pass validation without errors
        assert WorkerOptions.validate!(result) == result
      end)
    end

    test "never raises exceptions, always returns WorkerOptions struct" do
      # Test various error scenarios - should never crash
      error_scenarios = [
        %{some: "map"},           # Invalid type
        [:not, :keyword, :list],  # Invalid list structure
        {1, 2, 3},               # Tuple
        42,                      # Number
        :atom                    # Atom (but not valid config key)
      ]

      Enum.each(error_scenarios, fn invalid_config ->
        Application.put_env(:livekitex_agent, :default_worker_options, invalid_config)

        capture_log(fn ->
          assert %WorkerOptions{} = call_resolve_worker_options()
        end)
      end)
    end

    test "completes within performance requirements" do
      # Configuration resolution should complete within 100ms
      valid_config = TestFactories.valid_worker_config()
      Application.put_env(:livekitex_agent, :default_worker_options, valid_config)

      {time_microseconds, result} = :timer.tc(fn ->
        call_resolve_worker_options()
      end)

      time_milliseconds = time_microseconds / 1000

      assert %WorkerOptions{} = result
      assert time_milliseconds < 100, "Configuration resolution took #{time_milliseconds}ms, should be < 100ms"
    end

    test "emergency fallback uses system CPU count for worker pool size" do
      # Force emergency fallback
      Application.put_env(:livekitex_agent, :default_worker_options, "invalid")

      capture_log(fn ->
        result = call_resolve_worker_options()
        assert result.worker_pool_size == System.schedulers_online()
      end)
    end

    test "logs actionable error messages on configuration failure" do
      Application.put_env(:livekitex_agent, :default_worker_options, %{invalid: :config})

      log_output = capture_log(fn ->
        call_resolve_worker_options()
      end)

      # Should contain actionable guidance
      assert log_output =~ "Failed to resolve WorkerOptions configuration"
      assert log_output =~ "To fix this:"
      assert log_output =~ "config.exs"
      assert log_output =~ "entry_point"
      assert log_output =~ "Falling back to minimal configuration"
    end

    test "preserves user configuration values when valid" do
      # Test that valid user values are preserved, not overridden by defaults
      user_config = [
        worker_pool_size: 8,  # Non-default value
        timeout: 600_000,     # Non-default value (10 minutes)
        agent_name: "custom_test_agent",
        server_url: "wss://custom.livekit.cloud",
        max_concurrent_jobs: 25
      ]
      Application.put_env(:livekitex_agent, :default_worker_options, user_config)

      result = call_resolve_worker_options()

      assert result.worker_pool_size == 8
      assert result.timeout == 600_000
      assert result.agent_name == "custom_test_agent"
      assert result.server_url == "wss://custom.livekit.cloud"
      assert result.max_concurrent_jobs == 25
    end
  end

  describe "configuration resolution edge cases" do
    test "handles concurrent access safely" do
      # Test that concurrent calls don't interfere with each other
      valid_config = TestFactories.valid_worker_config()
      Application.put_env(:livekitex_agent, :default_worker_options, valid_config)

      tasks = for _ <- 1..10 do
        Task.async(fn ->
          call_resolve_worker_options()
        end)
      end

      results = Task.await_many(tasks)

      # All results should be valid and consistent
      Enum.each(results, fn result ->
        assert %WorkerOptions{} = result
        assert result.worker_pool_size == valid_config[:worker_pool_size]
      end)
    end

    test "handles partial configuration with some invalid values" do
      # Mix of valid and invalid values - should use defaults for invalid ones
      mixed_config = [
        worker_pool_size: 4,        # Valid
        timeout: -1000,             # Invalid - should get default
        agent_name: "test_agent",   # Valid
        max_concurrent_jobs: "ten", # Invalid - should get default
        server_url: "ws://localhost:7880" # Valid
      ]
      Application.put_env(:livekitex_agent, :default_worker_options, mixed_config)

      # This should trigger fallback due to validation errors
      log_output = capture_log(fn ->
        result = call_resolve_worker_options()
        assert %WorkerOptions{} = result
        # Should use emergency fallback due to validation errors
        assert result.agent_name == "emergency_fallback_agent"
      end)

      assert log_output =~ "Failed to resolve WorkerOptions configuration"
    end
  end
end
