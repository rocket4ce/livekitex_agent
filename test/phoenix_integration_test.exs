defmodule LivekitexAgent.PhoenixIntegrationTest do
  use ExUnit.Case, async: true
  require Logger

  alias LivekitexAgent.{WorkerOptions, JobContext}

  @moduletag :integration

  setup do
    # Ensure clean state for each test
    Application.delete_env(:livekitex_agent, :default_worker_options)
    :ok
  end

  describe "Phoenix zero-configuration integration" do
    test "Phoenix app can start with livekitex_agent dependency and no config" do
      # Simulate Phoenix startup scenario with no user configuration
      Application.delete_env(:livekitex_agent, :default_worker_options)

      # Should start successfully with defaults
      assert {:ok, _pid} = LivekitexAgent.Application.start(:normal, [])

      # Verify that WorkerManager is running
      assert Process.whereis(LivekitexAgent.WorkerManager) != nil

      # Verify that default configuration was applied by calling the function directly
      worker_options = apply(WorkerOptions, :from_config, [])
      assert worker_options.worker_pool_size == System.schedulers_online()
      assert worker_options.agent_name == "elixir_agent"
      assert is_function(worker_options.entry_point, 1)

      # Clean up
      Application.stop(:livekitex_agent)
      Process.sleep(100)
    end

    test "Phoenix app starts without KeyError crashes" do
      # This is the specific bug fix - ensure no KeyError on worker_pool_size
      Application.delete_env(:livekitex_agent, :default_worker_options)

      # Start application and verify no crashes
      assert {:ok, _pid} = LivekitexAgent.Application.start(:normal, [])

      # Verify WorkerManager can access worker_pool_size without KeyError
      worker_manager_pid = Process.whereis(LivekitexAgent.WorkerManager)
      assert worker_manager_pid != nil
      assert Process.alive?(worker_manager_pid)

      # Clean up
      Application.stop(:livekitex_agent)
      Process.sleep(100)
    end

    test "auto-generated entry_point function works correctly" do
      # Test the auto-generated entry point used in zero-config scenarios
      job_context = %JobContext{
        job_id: "test_job_123",
        room: %{name: "test_room"},
        participants: %{},
        metadata: %{},
        process_info: %{},
        callbacks: %{},
        tasks: %{},
        logging_context: %{},
        created_at: DateTime.utc_now(),
        status: :created,
        error_count: 0,
        max_errors: 5
      }

      # Should complete without errors
      assert :ok = LivekitexAgent.ExampleTools.auto_entry_point(job_context)
    end
  end

  describe "Phoenix custom configuration integration" do
    test "Phoenix app respects custom worker_pool_size from config" do
      # Configure custom worker_pool_size
      Application.put_env(:livekitex_agent, :default_worker_options, [
        worker_pool_size: 8,
        agent_name: "custom_phoenix_agent"
      ])

      # Start application
      assert {:ok, _pid} = LivekitexAgent.Application.start(:normal, [])

      # Verify custom configuration is applied
      worker_options = apply(WorkerOptions, :from_config, [])
      assert worker_options.worker_pool_size == 8
      assert worker_options.agent_name == "custom_phoenix_agent"

      # Verify defaults are still applied for unspecified values
      assert worker_options.timeout == 300_000
      assert worker_options.server_url == "ws://localhost:7880"

      # Clean up
      Application.stop(:livekitex_agent)
      Process.sleep(100)
    end

    test "Phoenix app handles partial configuration correctly" do
      # Test partial configuration scenario
      Application.put_env(:livekitex_agent, :default_worker_options, [
        worker_pool_size: 4,
        server_url: "ws://example.com:7880"
      ])

      assert {:ok, _pid} = LivekitexAgent.Application.start(:normal, [])

      worker_options = apply(WorkerOptions, :from_config, [])

      # Custom values
      assert worker_options.worker_pool_size == 4
      assert worker_options.server_url == "ws://example.com:7880"

      # Default values for missing config
      assert worker_options.agent_name == "elixir_agent"
      assert worker_options.timeout == 300_000
      assert is_function(worker_options.entry_point, 1)

      # Clean up
      Application.stop(:livekitex_agent)
      Process.sleep(100)
    end
  end

  describe "Phoenix error handling and recovery" do
    test "Application handles configuration validation errors gracefully" do
      # Test invalid configuration
      Application.put_env(:livekitex_agent, :default_worker_options, [
        worker_pool_size: -1  # Invalid value
      ])

      # Should still start due to error recovery in Application module
      assert {:ok, _pid} = LivekitexAgent.Application.start(:normal, [])

      # Verify fallback configuration was used
      assert Process.whereis(LivekitexAgent.WorkerManager) != nil

      # Clean up
      Application.stop(:livekitex_agent)
      Process.sleep(100)
    end

    test "Application provides clear error messages for configuration issues" do
      # Test that validate! provides clear error messages
      invalid_options = apply(WorkerOptions, :new, [[
        entry_point: &LivekitexAgent.ExampleTools.auto_entry_point/1,
        worker_pool_size: -1
      ]])

      assert_raise ArgumentError, ~r/Invalid worker_pool_size.*Must be positive integer/, fn ->
        apply(WorkerOptions, :validate!, [invalid_options])
      end
    end
  end
end
