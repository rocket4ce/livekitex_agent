defmodule LivekitexAgent.TestFactories do
  @moduledoc """
  Test data factories for generating valid and invalid WorkerOptions
  and configuration data for testing edge cases.

  Based on contracts/configuration-api.md requirements.
  """

  alias LivekitexAgent.WorkerOptions

  @doc """
  Generate valid WorkerOptions configuration with defaults.
  """
  def valid_worker_config(overrides \\ []) do
    defaults = [
      worker_pool_size: 4,
      timeout: 300_000,
      entry_point: fn _ctx -> :ok end,
      agent_name: "test_agent",
      server_url: "wss://test.livekit.cloud",
      api_key: "test_api_key",
      api_secret: "test_api_secret",
      max_concurrent_jobs: 10,
      health_check_port: 8080,
      load_threshold: 0.8,
      graceful_shutdown_timeout: 30_000
    ]

    Keyword.merge(defaults, overrides)
  end

  @doc """
  Generate minimal valid WorkerOptions configuration.
  """
  def minimal_worker_config(overrides \\ []) do
    minimal = [
      worker_pool_size: 1,
      timeout: 60_000,
      entry_point: fn _ctx -> :ok end
    ]

    Keyword.merge(minimal, overrides)
  end

  @doc """
  Generate emergency fallback WorkerOptions configuration.
  """
  def emergency_fallback_config do
    [
      worker_pool_size: System.schedulers_online(),
      timeout: 300_000,
      entry_point: fn _ctx -> :ok end,
      agent_name: "emergency_fallback_agent",
      max_concurrent_jobs: 1
    ]
  end

  @doc """
  Generate invalid configuration scenarios for testing error handling.
  """
  def invalid_worker_configs do
    %{
      negative_worker_pool_size: [worker_pool_size: -1, entry_point: fn _ctx -> :ok end],
      zero_worker_pool_size: [worker_pool_size: 0, entry_point: fn _ctx -> :ok end],
      negative_timeout: [worker_pool_size: 4, timeout: -1000, entry_point: fn _ctx -> :ok end],
      invalid_server_url: [worker_pool_size: 4, server_url: "not-a-url", entry_point: fn _ctx -> :ok end],
      invalid_port_too_low: [worker_pool_size: 4, health_check_port: 0, entry_point: fn _ctx -> :ok end],
      invalid_port_too_high: [worker_pool_size: 4, health_check_port: 70_000, entry_point: fn _ctx -> :ok end],
      invalid_load_threshold_negative: [worker_pool_size: 4, load_threshold: -0.1, entry_point: fn _ctx -> :ok end],
      invalid_load_threshold_too_high: [worker_pool_size: 4, load_threshold: 1.1, entry_point: fn _ctx -> :ok end],
      missing_required_fields: [timeout: 300_000], # Missing worker_pool_size and entry_point
      wrong_types: [worker_pool_size: "not_an_integer", entry_point: fn _ctx -> :ok end]
    }
  end

  @doc """
  Generate various invalid input types for WorkerManager testing.
  """
  def invalid_worker_manager_inputs do
    %{
      empty_list: [],
      nil_value: nil,
      wrong_struct: %{some: :map},
      string_value: "invalid",
      integer_value: 42,
      atom_value: :invalid
    }
  end

  @doc """
  Generate Application environment configurations for testing.
  """
  def application_env_configs do
    %{
      valid_config: [
        default_worker_options: valid_worker_config()
      ],
      minimal_config: [
        default_worker_options: minimal_worker_config()
      ],
      empty_config: [
        default_worker_options: []
      ],
      nil_config: [
        default_worker_options: nil
      ],
      missing_config: [],
      invalid_config_type: [
        default_worker_options: "not_a_keyword_list"
      ]
    }
  end

  @doc """
  Build a WorkerOptions struct from configuration.
  Useful for testing the from_config/1 function.
  """
  def build_worker_options(config \\ nil) do
    config = config || valid_worker_config()
    WorkerOptions.from_config(config)
  end

  @doc """
  Build a valid WorkerOptions struct directly.
  """
  def build_valid_worker_options(overrides \\ []) do
    config = valid_worker_config(overrides)
    struct(WorkerOptions, config)
  end

  @doc """
  Generate edge case scenarios for configuration resolution testing.
  """
  def configuration_resolution_scenarios do
    %{
      # Successful scenarios
      with_user_config: %{
        env_config: [default_worker_options: valid_worker_config()],
        expected_result: :success,
        description: "Normal configuration with user-provided options"
      },
      with_minimal_config: %{
        env_config: [default_worker_options: minimal_worker_config()],
        expected_result: :success,
        description: "Minimal valid configuration"
      },
      with_empty_list_config: %{
        env_config: [default_worker_options: []],
        expected_result: :success,
        description: "Empty configuration list should use defaults"
      },

      # Fallback scenarios
      with_nil_config: %{
        env_config: [default_worker_options: nil],
        expected_result: :fallback,
        description: "Nil configuration should trigger fallback"
      },
      with_no_config: %{
        env_config: [],
        expected_result: :fallback,
        description: "Missing configuration should trigger fallback"
      },
      with_invalid_config_type: %{
        env_config: [default_worker_options: "not_a_list"],
        expected_result: :fallback,
        description: "Invalid configuration type should trigger fallback"
      },
      with_invalid_config_values: %{
        env_config: [default_worker_options: [worker_pool_size: -1]],
        expected_result: :fallback,
        description: "Invalid configuration values should trigger fallback"
      }
    }
  end

  @doc """
  Generate Phoenix integration test scenarios.
  """
  def phoenix_integration_scenarios do
    %{
      normal_startup: %{
        config: valid_worker_config(),
        expected_result: :success,
        description: "Normal Phoenix startup with valid configuration"
      },
      minimal_startup: %{
        config: minimal_worker_config(),
        expected_result: :success,
        description: "Phoenix startup with minimal configuration"
      },
      no_config_startup: %{
        config: nil,
        expected_result: :success_with_fallback,
        description: "Phoenix startup without configuration should use fallback"
      },
      invalid_config_startup: %{
        config: [worker_pool_size: -1],
        expected_result: :success_with_fallback,
        description: "Phoenix startup with invalid configuration should use fallback"
      }
    }
  end

  @doc """
  Helper to set up Application environment for testing.
  """
  def setup_application_env(config) do
    # Store original config
    original_config = Application.get_env(:livekitex_agent, :default_worker_options)

    # Set test config
    case config do
      nil ->
        Application.delete_env(:livekitex_agent, :default_worker_options)
      config ->
        Application.put_env(:livekitex_agent, :default_worker_options, config)
    end

    # Return cleanup function
    fn ->
      case original_config do
        nil ->
          Application.delete_env(:livekitex_agent, :default_worker_options)
        config ->
          Application.put_env(:livekitex_agent, :default_worker_options, config)
      end
    end
  end

  @doc """
  Helper to capture log messages during test execution.
  """
  def capture_log(fun) when is_function(fun, 0) do
    ExUnit.CaptureLog.capture_log(fun)
  end
end
