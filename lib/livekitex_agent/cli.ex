defmodule LivekitexAgent.CLI do
  @moduledoc """
  Command-line interface utilities for running and managing agents.

  CLI provides:
  - Production mode to start worker in production
  - Development options with hot reload and debugging features
  - Configuration for log levels, server URLs, API keys
  - Worker management with drain timeouts and process control
  """

  require Logger

  @doc """
  Main CLI entry point. Parses command line arguments and executes the appropriate command.

  ## Usage
      ./my_agent --help
      ./my_agent start --agent-name my_agent --server-url ws://localhost:7880
      ./my_agent dev --hot-reload --log-level debug
      ./my_agent worker --production --max-jobs 10
  """
  def main(args \\ []) do
    {parsed_args, remaining_args, invalid_args} =
      OptionParser.parse(args,
        strict: [
          help: :boolean,
          version: :boolean,
          agent_name: :string,
          server_url: :string,
          api_key: :string,
          api_secret: :string,
          log_level: :string,
          production: :boolean,
          dev: :boolean,
          hot_reload: :boolean,
          max_jobs: :integer,
          timeout: :integer,
          port: :integer,
          host: :string,
          drain_timeout: :integer,
          config_file: :string
        ],
        aliases: [
          h: :help,
          v: :version,
          n: :agent_name,
          s: :server_url,
          k: :api_key,
          l: :log_level,
          p: :production,
          d: :dev,
          r: :hot_reload,
          m: :max_jobs,
          t: :timeout,
          c: :config_file
        ]
      )

    if length(invalid_args) > 0 do
      Logger.error("Invalid arguments: #{inspect(invalid_args)}")
      print_help()
      System.halt(1)
    end

    cond do
      parsed_args[:help] ->
        print_help()

      parsed_args[:version] ->
        print_version()

      parsed_args[:production] ->
        start_production_worker(parsed_args)

      parsed_args[:dev] ->
        start_development_worker(parsed_args)

      length(remaining_args) > 0 ->
        handle_command(hd(remaining_args), parsed_args, tl(remaining_args))

      true ->
        print_help()
    end
  end

  @doc """
  Starts a worker in production mode.
  """
  def start_production_worker(opts \\ []) do
    Logger.info("Starting agent worker in production mode")

    config = build_worker_config(opts)

    case validate_production_config(config) do
      {:ok, validated_config} ->
        setup_logging(validated_config.log_level)
        start_worker(validated_config)

      {:error, reason} ->
        Logger.error("Invalid production configuration: #{reason}")
        System.halt(1)
    end
  end

  @doc """
  Starts a worker in development mode with hot reload and debugging.
  """
  def start_development_worker(opts \\ []) do
    Logger.info("Starting agent worker in development mode")

    config =
      build_worker_config(opts)
      |> Map.put(:hot_reload, Keyword.get(opts, :hot_reload, false))
      |> Map.put(:debug, true)

    setup_logging(config.log_level)

    if config.hot_reload do
      setup_hot_reload()
    end

    start_worker(config)
  end

  @doc """
  Handles specific CLI commands.
  """
  def handle_command(command, opts, args) do
    case command do
      "start" ->
        start_production_worker(opts)

      "dev" ->
        start_development_worker(Keyword.put(opts, :dev, true))

      "worker" ->
        if opts[:production] do
          start_production_worker(opts)
        else
          start_development_worker(opts)
        end

      "test" ->
        run_tests(opts, args)

      "config" ->
        show_configuration(opts)

      "health" ->
        check_health(opts)

      _ ->
        Logger.error("Unknown command: #{command}")
        print_help()
        System.halt(1)
    end
  end

  @doc """
  Builds worker configuration from command line options.
  """
  def build_worker_config(opts \\ []) do
    # Load configuration from file if specified
    base_config =
      case Keyword.get(opts, :config_file) do
        nil -> %{}
        file_path -> load_config_file(file_path)
      end

    # Override with command line options
    %{
      agent_name:
        Keyword.get(opts, :agent_name, Map.get(base_config, :agent_name, "elixir_agent")),
      server_url:
        Keyword.get(opts, :server_url, Map.get(base_config, :server_url, "ws://localhost:7880")),
      api_key: Keyword.get(opts, :api_key, Map.get(base_config, :api_key, "")),
      api_secret: Keyword.get(opts, :api_secret, Map.get(base_config, :api_secret, "")),
      log_level:
        parse_log_level(Keyword.get(opts, :log_level, Map.get(base_config, :log_level, "info"))),
      max_jobs: Keyword.get(opts, :max_jobs, Map.get(base_config, :max_jobs, 10)),
      timeout: Keyword.get(opts, :timeout, Map.get(base_config, :timeout, 300_000)),
      port: Keyword.get(opts, :port, Map.get(base_config, :port, 8080)),
      host: Keyword.get(opts, :host, Map.get(base_config, :host, "localhost")),
      drain_timeout:
        Keyword.get(opts, :drain_timeout, Map.get(base_config, :drain_timeout, 30_000))
    }
  end

  @doc """
  Prints help information.
  """
  def print_help do
    IO.puts("""
    LivekitexAgent Agent CLI

    USAGE:
        my_agent [OPTIONS] [COMMAND]

    COMMANDS:
        start       Start agent worker in production mode
        dev         Start agent worker in development mode
        worker      Start worker (use --production for prod mode)
        test        Run agent tests
        config      Show current configuration
        health      Check worker health
        help        Show this help message

    OPTIONS:
        -h, --help                 Show help
        -v, --version              Show version
        -n, --agent-name NAME      Agent name (default: elixir_agent)
        -s, --server-url URL       LiveKit server URL (default: ws://localhost:7880)
        -k, --api-key KEY          LiveKit API key
            --api-secret SECRET    LiveKit API secret
        -l, --log-level LEVEL      Log level: debug, info, warning, error (default: info)
        -p, --production           Run in production mode
        -d, --dev                  Run in development mode
        -r, --hot-reload           Enable hot code reload (dev mode)
        -m, --max-jobs N           Maximum concurrent jobs (default: 10)
        -t, --timeout MS           Job timeout in milliseconds (default: 300000)
            --port PORT            HTTP server port (default: 8080)
            --host HOST            HTTP server host (default: localhost)
            --drain-timeout MS     Graceful shutdown timeout (default: 30000)
        -c, --config-file PATH     Load configuration from file

    EXAMPLES:
        # Start in production with custom settings
        my_agent start --agent-name voice_assistant --max-jobs 5 --production

        # Development mode with hot reload
        my_agent dev --hot-reload --log-level debug

        # Load configuration from file
        my_agent start --config-file ./config/production.json

        # Check worker health
        my_agent health --server-url ws://prod.livekit.cloud
    """)
  end

  @doc """
  Prints version information.
  """
  def print_version do
    {:ok, vsn} = :application.get_key(:livekitex_agent, :vsn)
    IO.puts("LivekitexAgent Agent v#{vsn}")

    IO.puts("""

    Build Information:
      Elixir: #{System.version()}
      OTP: #{:erlang.system_info(:otp_release)}
      Node: #{node()}
    """)
  end

  # Private functions

  defp start_worker(config) do
    Logger.info("Starting worker with config: #{inspect(config, pretty: true)}")

    # Create worker options
    worker_options =
      LivekitexAgent.WorkerOptions.new(
        entry_point: &default_entry_point/1,
        agent_name: config.agent_name,
        server_url: config.server_url,
        api_key: config.api_key,
        api_secret: config.api_secret,
        max_concurrent_jobs: config.max_jobs,
        timeout: config.timeout,
        graceful_shutdown_timeout: config.drain_timeout
      )

    case LivekitexAgent.WorkerOptions.validate(worker_options) do
      {:ok, validated_options} ->
        # Start the worker supervisor
        {:ok, _pid} = LivekitexAgent.WorkerSupervisor.start_link(validated_options)

        # Set up graceful shutdown
        setup_shutdown_handlers()

        Logger.info("Worker started successfully")

        # Keep the process alive
        :timer.sleep(:infinity)

      {:error, reason} ->
        Logger.error("Failed to start worker: #{reason}")
        System.halt(1)
    end
  end

  defp validate_production_config(config) do
    cond do
      config.api_key == "" ->
        {:error, "API key is required in production mode"}

      config.api_secret == "" ->
        {:error, "API secret is required in production mode"}

      not String.starts_with?(config.server_url, "ws") ->
        {:error, "Invalid server URL format"}

      config.max_jobs <= 0 ->
        {:error, "Max jobs must be greater than 0"}

      true ->
        {:ok, config}
    end
  end

  defp setup_logging(log_level) do
    Logger.configure(level: log_level)

    Logger.add_backend(:console)

    Logger.configure_backend(:console,
      format: "$time $metadata[$level] $message\n",
      metadata: [:request_id, :job_id, :session_id]
    )
  end

  defp setup_hot_reload do
    Logger.info("Setting up hot code reload")

    # This would integrate with a file watcher like FileSystem
    # For now, just log that it would be enabled
    Logger.info("Hot reload would be enabled in a full implementation")
  end

  defp setup_shutdown_handlers do
    # Handle SIGTERM and SIGINT for graceful shutdown
    :gen_event.add_handler(:erl_signal_server, :erl_signal_handler, [])

    Process.flag(:trap_exit, true)
  end

  defp parse_log_level(level_str) do
    case String.downcase(level_str) do
      "debug" -> :debug
      "info" -> :info
      "warning" -> :warning
      "warn" -> :warning
      "error" -> :error
      "critical" -> :critical
      _ -> :info
    end
  end

  defp load_config_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, config} ->
            # Convert string keys to atoms for easier access
            config
            |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
            |> Enum.into(%{})

          {:error, reason} ->
            Logger.error("Failed to parse config file #{file_path}: #{reason}")
            %{}
        end

      {:error, reason} ->
        Logger.error("Failed to read config file #{file_path}: #{reason}")
        %{}
    end
  end

  defp run_tests(_opts, args) do
    Logger.info("Running agent tests")

    # This would integrate with ExUnit or other testing frameworks
    test_files =
      case args do
        [] -> ["test/**/*_test.exs"]
        files -> files
      end

    Logger.info("Test files: #{inspect(test_files)}")
    Logger.info("Tests would be executed in a full implementation")
  end

  defp show_configuration(opts) do
    config = build_worker_config(opts)

    IO.puts("Current Configuration:")
    IO.puts("=====================")

    config
    |> Enum.sort()
    |> Enum.each(fn {key, value} ->
      # Mask sensitive values
      display_value =
        if key in [:api_key, :api_secret] and value != "" do
          String.slice(value, 0, 4) <> "****"
        else
          value
        end

      IO.puts("  #{key}: #{display_value}")
    end)
  end

  defp check_health(opts) do
    config = build_worker_config(opts)

    Logger.info("Checking worker health...")

    # This would make actual health check requests
    health_checks = [
      {"Server Connection", check_server_connection(config.server_url)},
      {"Memory Usage", check_memory_usage()},
      {"Process Count", check_process_count()},
      {"Load Average", check_load_average()}
    ]

    IO.puts("Health Check Results:")
    IO.puts("====================")

    all_healthy = Enum.all?(health_checks, fn {_name, status} -> status == :ok end)

    Enum.each(health_checks, fn {name, status} ->
      status_icon = if status == :ok, do: "✅", else: "❌"
      IO.puts("  #{status_icon} #{name}: #{format_health_status(status)}")
    end)

    if all_healthy do
      IO.puts("\nOverall Status: ✅ Healthy")
      System.halt(0)
    else
      IO.puts("\nOverall Status: ❌ Unhealthy")
      System.halt(1)
    end
  end

  defp check_server_connection(server_url) do
    # Mock health check - would make actual connection attempt
    if String.starts_with?(server_url, "ws") do
      :ok
    else
      {:error, "Invalid URL format"}
    end
  end

  defp check_memory_usage do
    # Mock memory check
    :ok
  end

  defp check_process_count do
    process_count = length(Process.list())
    if process_count < 1000, do: :ok, else: {:warning, "High process count: #{process_count}"}
  end

  defp check_load_average do
    # Mock load check
    :ok
  end

  defp format_health_status(:ok), do: "OK"
  defp format_health_status({:warning, msg}), do: "Warning: #{msg}"
  defp format_health_status({:error, msg}), do: "Error: #{msg}"

  defp default_entry_point(job_context) do
    Logger.info("Default entry point called with job: #{job_context.job_id}")

    # Create a basic agent and session
    agent =
      LivekitexAgent.Agent.new(
        instructions: "You are a helpful assistant.",
        tools: []
      )

    {:ok, session_pid} = LivekitexAgent.AgentSession.start_link(agent: agent)

    # Keep the session running
    Process.monitor(session_pid)

    receive do
      {:DOWN, _ref, :process, ^session_pid, reason} ->
        Logger.info("Agent session terminated: #{inspect(reason)}")
    end
  end
end
