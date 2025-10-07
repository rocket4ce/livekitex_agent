defmodule LivekitexAgent.WorkerManagerTest do
  @moduledoc """
  Test WorkerManager initialization with various input types and validation errors.

  Tests verify proper error messages and successful initialization with valid inputs
  as specified in tasks T006 from 005-fix-phoenix-integration.
  """

  use ExUnit.Case, async: false
  alias LivekitexAgent.{WorkerManager, WorkerOptions, TestFactories}

  describe "WorkerManager initialization" do
    test "starts successfully with valid WorkerOptions struct" do
      valid_options = TestFactories.valid_worker_config()
                     |> WorkerOptions.from_config()

      {:ok, pid} = WorkerManager.start_link(valid_options)
      assert Process.alive?(pid)

      # Verify it can handle basic operations
      status = WorkerManager.get_status()
      assert %{worker_pool: worker_pool} = status
      assert map_size(worker_pool) == valid_options.worker_pool_size

      # Clean up
      GenServer.stop(pid)
    end

    test "starts successfully with minimal WorkerOptions struct" do
      minimal_options = TestFactories.minimal_worker_config()
                       |> WorkerOptions.from_config()

      {:ok, pid} = WorkerManager.start_link(minimal_options)
      assert Process.alive?(pid)

      status = WorkerManager.get_status()
      assert %{worker_pool: worker_pool} = status
      assert map_size(worker_pool) == minimal_options.worker_pool_size

      # Clean up
      GenServer.stop(pid)
    end

    test "raises ArgumentError when passed nil" do
      expected_error = ArgumentError
      expected_message = "WorkerManager requires WorkerOptions struct, got: nil"

      assert_raise expected_error, fn ->
        WorkerManager.start_link(nil)
      end

      # Verify the error message contains helpful guidance
      try do
        WorkerManager.start_link(nil)
      rescue
        e in ArgumentError ->
          assert String.contains?(e.message, expected_message)
          assert String.contains?(e.message, "Problem: WorkerManager cannot start without valid configuration")
          assert String.contains?(e.message, "Fix: Ensure Application.resolve_worker_options/0 returns a valid WorkerOptions struct")
          assert String.contains?(e.message, "Suggested: Check your config.exs has :livekitex_agent, :default_worker_options configured")
      end
    end

    test "raises ArgumentError when passed empty list" do
      expected_error = ArgumentError
      expected_message = "WorkerManager requires WorkerOptions struct, got: list []"

      assert_raise expected_error, fn ->
        WorkerManager.start_link([])
      end

      # Verify the error message contains helpful guidance
      try do
        WorkerManager.start_link([])
      rescue
        e in ArgumentError ->
          assert String.contains?(e.message, expected_message)
          assert String.contains?(e.message, "Problem: Raw configuration list passed instead of WorkerOptions struct")
          assert String.contains?(e.message, "Fix: Convert configuration to WorkerOptions struct using WorkerOptions.from_config/1")
          assert String.contains?(e.message, "Suggested: Use Application.resolve_worker_options/0 instead of raw config")
      end
    end

    test "raises ArgumentError when passed keyword list configuration" do
      config_list = TestFactories.valid_worker_config()
      expected_error = ArgumentError

      assert_raise expected_error, fn ->
        WorkerManager.start_link(config_list)
      end

      # Verify the error message mentions the specific invalid input
      try do
        WorkerManager.start_link(config_list)
      rescue
        e in ArgumentError ->
          assert String.contains?(e.message, "WorkerManager requires WorkerOptions struct, got: list")
          assert String.contains?(e.message, "Problem: Raw configuration list passed instead of WorkerOptions struct")
      end
    end

    test "raises ArgumentError when passed plain map" do
      plain_map = %{worker_pool_size: 4, timeout: 300_000}
      expected_error = ArgumentError

      assert_raise expected_error, fn ->
        WorkerManager.start_link(plain_map)
      end

      # Verify the error message provides helpful guidance
      try do
        WorkerManager.start_link(plain_map)
      rescue
        e in ArgumentError ->
          assert String.contains?(e.message, "WorkerManager requires WorkerOptions struct, got: plain map")
          assert String.contains?(e.message, "Problem: Plain map passed instead of WorkerOptions struct")
          assert String.contains?(e.message, "Fix: Convert map to WorkerOptions struct using WorkerOptions.from_config/1")
      end
    end

    test "raises ArgumentError when passed wrong struct type" do
      wrong_struct = %Date{year: 2025, month: 10, day: 7}
      expected_error = ArgumentError

      assert_raise expected_error, fn ->
        WorkerManager.start_link(wrong_struct)
      end

      # Verify the error message mentions the wrong struct type
      try do
        WorkerManager.start_link(wrong_struct)
      rescue
        e in ArgumentError ->
          assert String.contains?(e.message, "WorkerManager requires WorkerOptions struct, got: Date")
          assert String.contains?(e.message, "Problem: Wrong struct type passed to WorkerManager")
          assert String.contains?(e.message, "Fix: Pass LivekitexAgent.WorkerOptions struct instead")
      end
    end

    test "raises ArgumentError when passed string" do
      invalid_string = "invalid_config_string"
      expected_error = ArgumentError

      assert_raise expected_error, fn ->
        WorkerManager.start_link(invalid_string)
      end

      # Verify the error message provides guidance for this common mistake
      try do
        WorkerManager.start_link(invalid_string)
      rescue
        e in ArgumentError ->
          assert String.contains?(e.message, "WorkerManager requires WorkerOptions struct, got:")
          assert String.contains?(e.message, "Problem: Invalid input type - expected %LivekitexAgent.WorkerOptions{}")
          assert String.contains?(e.message, "Suggested: Use Application.resolve_worker_options/0 or WorkerOptions.from_config/1")
      end
    end

    test "raises ArgumentError when passed integer" do
      invalid_integer = 42
      expected_error = ArgumentError

      assert_raise expected_error, fn ->
        WorkerManager.start_link(invalid_integer)
      end

      # Verify the error message is helpful
      try do
        WorkerManager.start_link(invalid_integer)
      rescue
        e in ArgumentError ->
          assert String.contains?(e.message, "WorkerManager requires WorkerOptions struct, got:")
          assert String.contains?(e.message, "Problem: Invalid input type - expected %LivekitexAgent.WorkerOptions{}")
      end
    end

    test "error messages are actionable and helpful" do
      # Test that all error messages follow the standard format
      invalid_inputs = [
        nil,
        [],
        %{some: "map"},
        "string",
        42,
        %Date{year: 2025, month: 10, day: 7}
      ]

      Enum.each(invalid_inputs, fn invalid_input ->
        try do
          WorkerManager.start_link(invalid_input)
          flunk("Expected ArgumentError for input: #{inspect(invalid_input)}")
        rescue
          e in ArgumentError ->
            # Verify all error messages have the required components
            assert String.contains?(e.message, "Problem:")
            assert String.contains?(e.message, "Fix:")
            assert String.contains?(e.message, "Suggested:")

            # Verify the message is informative about the actual vs expected type
            assert String.contains?(e.message, "WorkerManager requires WorkerOptions struct")
        end
      end)
    end

    test "successful initialization creates proper worker pool" do
      options = TestFactories.valid_worker_config([worker_pool_size: 2])
                |> WorkerOptions.from_config()

      {:ok, pid} = WorkerManager.start_link(options)

      # Verify the worker pool was created with the correct size
      status = WorkerManager.get_status()
      assert %{worker_pool: worker_pool} = status
      assert map_size(worker_pool) == 2

      # Verify each worker has the expected structure
      Enum.each(worker_pool, fn {worker_id, worker_info} ->
        assert is_binary(worker_id)
        assert %{
          id: ^worker_id,
          started_at: %DateTime{},
          job_count: 0
        } = worker_info
      end)

      # Clean up
      GenServer.stop(pid)
    end

    test "WorkerManager respects worker_pool_size from options" do
      # Test different pool sizes
      test_sizes = [1, 2, 4, 8]

      Enum.each(test_sizes, fn size ->
        options = TestFactories.valid_worker_config([worker_pool_size: size])
                  |> WorkerOptions.from_config()

        {:ok, pid} = WorkerManager.start_link(options)

        status = WorkerManager.get_status()
        assert %{worker_pool: worker_pool} = status
        assert map_size(worker_pool) == size

        GenServer.stop(pid)
      end)
    end
  end

  describe "WorkerManager with emergency fallback configuration" do
    test "starts with emergency fallback WorkerOptions" do
      # Create emergency fallback options (what Application.create_emergency_fallback/0 would create)
      emergency_options = WorkerOptions.from_config([
        entry_point: fn _ctx -> :ok end,
        worker_pool_size: System.schedulers_online(),
        agent_name: "emergency_fallback_agent",
        timeout: 300_000,
        max_concurrent_jobs: 1
      ])

      {:ok, pid} = WorkerManager.start_link(emergency_options)
      assert Process.alive?(pid)

      status = WorkerManager.get_status()
      assert %{worker_pool: worker_pool} = status
      assert map_size(worker_pool) == System.schedulers_online()

      # Clean up
      GenServer.stop(pid)
    end
  end
end
