defmodule LivekitexAgent.ApplicationFallbackTest do
  @moduledoc """
  Tests for the emergency fallback mechanism in Application.resolve_worker_options/0.

  These tests verify that the application can start successfully even when
  configuration fails, using emergency defaults to provide minimal functionality.

  Based on:
  - specs/005-fix-phoenix-integration/contracts/configuration-api.md
  - User Story 3 (P3): Graceful Fallback Mechanism

  Acceptance Criteria:
  - Fallback activates within 1 second
  - Emergency configuration is valid and functional
  - System provides basic functionality in degraded mode
  - Proper logging and telemetry for fallback activation
  """

  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  require Logger

  alias LivekitexAgent.WorkerOptions

  # Access to private resolve_worker_options function for testing
  defp call_resolve_worker_options do
    :erlang.apply(LivekitexAgent.Application, :resolve_worker_options, [])
  end

  setup do
    # Save original configuration
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

  describe "emergency fallback activation" do
    test "activates fallback when config is missing" do
      # Simulate missing configuration
      Application.delete_env(:livekitex_agent, :default_worker_options)

      {time_us, result} = :timer.tc(fn ->
        log =
          capture_log(fn ->
            result = call_resolve_worker_options()
            send(self(), {:result, result})
          end)

        receive do
          {:result, res} -> {res, log}
        end
      end)

      {result, log} = result
      time_ms = time_us / 1000

      # Performance requirement: < 1 second (1000ms)
      assert time_ms < 1000,
             "Fallback activation took #{time_ms}ms, expected < 1000ms"

      # Verify valid WorkerOptions struct returned
      assert %WorkerOptions{} = result
      assert result.agent_name == "emergency_fallback_agent"
      assert result.worker_pool_size == System.schedulers_online()
      assert result.timeout == 300_000
      assert result.max_concurrent_jobs == 1
      assert is_function(result.entry_point, 1)

      # Verify logging
      assert log =~ "emergency fallback"
      assert log =~ "minimal functionality"
    end

    test "activates fallback when config is nil" do
      Application.put_env(:livekitex_agent, :default_worker_options, nil)

      {time_us, result} = :timer.tc(fn ->
        call_resolve_worker_options()
      end)

      time_ms = time_us / 1000

      # Performance requirement
      assert time_ms < 1000,
             "Fallback activation took #{time_ms}ms, expected < 1000ms"

      # Verify valid fallback configuration
      assert %WorkerOptions{} = result
      assert result.agent_name == "emergency_fallback_agent"
    end

    test "activates fallback when config is invalid type" do
      # Test with string instead of keyword list
      Application.put_env(:livekitex_agent, :default_worker_options, "invalid_config")

      {time_us, log} = :timer.tc(fn ->
        capture_log(fn ->
          result = call_resolve_worker_options()
          send(self(), {:result, result})
        end)
      end)

      time_ms = time_us / 1000

      receive do
        {:result, result} ->
          # Performance requirement
          assert time_ms < 1000,
                 "Fallback activation took #{time_ms}ms, expected < 1000ms"

          # Verify valid fallback configuration
          assert %WorkerOptions{} = result
          assert result.agent_name == "emergency_fallback_agent"

          # Verify warning was logged
          assert log =~ "Invalid configuration type"
      end
    end

    test "activates fallback when WorkerOptions.from_config raises error" do
      # Provide configuration that will fail validation
      invalid_config = [
        worker_pool_size: -1,
        entry_point: fn _ctx -> :ok end
      ]

      Application.put_env(:livekitex_agent, :default_worker_options, invalid_config)

      {time_us, result} = :timer.tc(fn ->
        log =
          capture_log(fn ->
            result = call_resolve_worker_options()
            send(self(), {:result, result})
          end)

        receive do
          {:result, res} -> {res, log}
        end
      end)

      {result, log} = result
      time_ms = time_us / 1000

      # Performance requirement
      assert time_ms < 1000,
             "Fallback activation took #{time_ms}ms, expected < 1000ms"

      # Verify fallback was used
      assert %WorkerOptions{} = result
      assert result.agent_name == "emergency_fallback_agent"

      # Verify error was logged
      assert log =~ "Configuration resolution failed"
      assert log =~ "emergency fallback"
    end

    test "fallback provides minimal but functional configuration" do
      Application.delete_env(:livekitex_agent, :default_worker_options)

      result = call_resolve_worker_options()

      # Verify all required fields are present
      assert %WorkerOptions{} = result

      # Verify entry_point is callable
      assert is_function(result.entry_point, 1)
      assert result.entry_point.(%{}) == :ok

      # Verify worker pool size is reasonable
      assert result.worker_pool_size > 0
      assert result.worker_pool_size == System.schedulers_online()

      # Verify timeout is set
      assert result.timeout > 0

      # Verify agent name is set
      assert is_binary(result.agent_name)
      assert String.length(result.agent_name) > 0

      # Verify max concurrent jobs is conservative
      assert result.max_concurrent_jobs == 1
    end

    test "fallback configuration passes WorkerOptions validation" do
      Application.delete_env(:livekitex_agent, :default_worker_options)

      result = call_resolve_worker_options()

      # This should not raise - fallback config must be valid
      assert %WorkerOptions{} = WorkerOptions.validate!(result)
    end
  end

  describe "fallback activation logging and telemetry" do
    test "logs structured error data on configuration failure" do
      invalid_config = [worker_pool_size: -1, entry_point: fn _ctx -> :ok end]
      Application.put_env(:livekitex_agent, :default_worker_options, invalid_config)

      log =
        capture_log(fn ->
          call_resolve_worker_options()
        end)

      # Verify structured logging includes key information
      assert log =~ "config_resolution_failure"
      assert log =~ "error_type"
      assert log =~ "error_message"
      assert log =~ "suggested_fixes"
      assert log =~ "fallback_status"
      assert log =~ "emergency_defaults_active"
    end

    test "logs emergency fallback creation details" do
      Application.delete_env(:livekitex_agent, :default_worker_options)

      log =
        capture_log(fn ->
          call_resolve_worker_options()
        end)

      # Verify fallback creation is logged
      assert log =~ "emergency_fallback_creation"
      assert log =~ "fallback_config"
      assert log =~ "limitations"
      assert log =~ "recommended_action"
    end

    test "logs user-friendly error messages" do
      invalid_config = [worker_pool_size: -1, entry_point: fn _ctx -> :ok end]
      Application.put_env(:livekitex_agent, :default_worker_options, invalid_config)

      log =
        capture_log(fn ->
          call_resolve_worker_options()
        end)

      # Verify user-friendly guidance is provided
      assert log =~ "Failed to resolve WorkerOptions configuration"
      assert log =~ "To fix this:"
      assert log =~ "Ensure your config.exs"
      assert log =~ "Falling back to emergency defaults"
    end

    test "includes performance metrics in logs" do
      Application.delete_env(:livekitex_agent, :default_worker_options)

      log =
        capture_log(fn ->
          call_resolve_worker_options()
        end)

      # Verify duration is logged
      assert log =~ "duration_ms"
    end
  end

  describe "fallback performance requirements" do
    test "fallback activation meets performance SLA (< 1s)" do
      test_cases = [
        {:missing_config, fn -> Application.delete_env(:livekitex_agent, :default_worker_options) end},
        {:nil_config, fn -> Application.put_env(:livekitex_agent, :default_worker_options, nil) end},
        {:invalid_type, fn -> Application.put_env(:livekitex_agent, :default_worker_options, "invalid") end},
        {:invalid_value, fn -> Application.put_env(:livekitex_agent, :default_worker_options, [worker_pool_size: -1, entry_point: fn _ctx -> :ok end]) end}
      ]

      Enum.each(test_cases, fn {scenario, setup_fn} ->
        setup_fn.()

        {time_us, result} = :timer.tc(fn ->
          capture_log(fn ->
            call_resolve_worker_options()
          end)
        end)

        time_ms = time_us / 1000

        assert time_ms < 1000,
               "Fallback activation for #{scenario} took #{time_ms}ms, expected < 1000ms"

        assert %WorkerOptions{} = result
      end)
    end

    test "repeated fallback activations remain performant" do
      Application.delete_env(:livekitex_agent, :default_worker_options)

      times =
        Enum.map(1..10, fn _iteration ->
          {time_us, _result} = :timer.tc(fn ->
            capture_log(fn ->
              call_resolve_worker_options()
            end)
          end)

          time_us / 1000
        end)

      avg_time = Enum.sum(times) / length(times)
      max_time = Enum.max(times)

      assert avg_time < 1000, "Average fallback time #{avg_time}ms exceeds 1000ms"
      assert max_time < 1000, "Max fallback time #{max_time}ms exceeds 1000ms"
    end
  end

  describe "fallback behavior with various error types" do
    test "handles ArgumentError from invalid configuration" do
      invalid_config = [worker_pool_size: -1, entry_point: fn _ctx -> :ok end]
      Application.put_env(:livekitex_agent, :default_worker_options, invalid_config)

      log =
        capture_log(fn ->
          result = call_resolve_worker_options()
          send(self(), {:result, result})
        end)

      receive do
        {:result, result} ->
          assert %WorkerOptions{} = result
          assert result.agent_name == "emergency_fallback_agent"
          assert log =~ "ArgumentError"
      end
    end

    test "handles missing required fields" do
      incomplete_config = [timeout: 300_000]
      Application.put_env(:livekitex_agent, :default_worker_options, incomplete_config)

      _log =
        capture_log(fn ->
          result = call_resolve_worker_options()
          send(self(), {:result, result})
        end)

      receive do
        {:result, result} ->
          assert %WorkerOptions{} = result
          assert result.agent_name == "emergency_fallback_agent"
      end
    end

    test "handles configuration with wrong data types" do
      wrong_type_config = [
        worker_pool_size: "not_an_integer",
        entry_point: "not_a_function"
      ]

      Application.put_env(:livekitex_agent, :default_worker_options, wrong_type_config)

      result =
        capture_log(fn ->
          call_resolve_worker_options()
        end)

      assert %WorkerOptions{} = result
      assert result.agent_name == "emergency_fallback_agent"
    end
  end

  describe "fallback integration with WorkerManager" do
    test "WorkerManager can initialize with fallback configuration" do
      Application.delete_env(:livekitex_agent, :default_worker_options)

      fallback_options =
        capture_log(fn ->
          call_resolve_worker_options()
        end)

      # This should not raise - WorkerManager should accept fallback config
      assert %WorkerOptions{} = fallback_options

      # Verify it meets WorkerManager's requirements
      assert is_struct(fallback_options, WorkerOptions)
      assert fallback_options.worker_pool_size > 0
      assert is_function(fallback_options.entry_point, 1)
    end
  end
end
