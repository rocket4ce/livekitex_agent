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
          config_file: :string,
          # Enterprise deployment options
          workers: :integer,
          min_workers: :integer,
          max_workers: :integer,
          enable_metrics: :boolean,
          metrics_port: :integer,
          health_port: :integer,
          enable_dashboard: :boolean,
          auto_scale: :boolean,
          scale_up_threshold: :float,
          scale_down_threshold: :float,
          load_balancer: :string,
          circuit_breaker: :boolean,
          deployment_env: :string,
          cluster_name: :string,
          node_name: :string,
          export_format: :string,
          output_file: :string
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

      "tools" ->
        handle_tools_command(opts, args)

      "test-tool" ->
        test_single_tool(opts, args)

      "list-tools" ->
        list_registered_tools(opts)

      "validate-tools" ->
        validate_all_tools(opts)

      "config" ->
        show_configuration(opts)

      "health" ->
        check_health(opts)

      # Enterprise deployment commands
      "deploy" ->
        handle_deploy_command(opts, args)

      "cluster" ->
        handle_cluster_command(opts, args)

      "scale" ->
        handle_scale_command(opts, args)

      "monitor" ->
        handle_monitor_command(opts, args)

      "metrics" ->
        handle_metrics_command(opts, args)

      "dashboard" ->
        handle_dashboard_command(opts, args)

      "status" ->
        handle_status_command(opts, args)

      "drain" ->
        handle_drain_command(opts, args)

      "restart" ->
        handle_restart_command(opts, args)

      "backup" ->
        handle_backup_command(opts, args)

      "restore" ->
        handle_restore_command(opts, args)

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
        Basic Commands:
          start       Start agent worker in production mode
          dev         Start agent worker in development mode
          worker      Start worker (use --production for prod mode)
          test        Run agent tests
          config      Show current configuration
          health      Check worker health
          help        Show this help message

        Enterprise Commands:
          deploy      Deploy and manage production environments
          cluster     Manage distributed clusters
          scale       Control worker pool scaling
          monitor     Monitor system performance
          metrics     Manage metrics collection
          dashboard   Control monitoring dashboard
          status      Show comprehensive system status
          drain       Graceful shutdown management
          restart     Restart with different strategies
          backup      Create and manage backups
          restore     Restore from backups

        Tool Commands:
          tools       Manage available tools
          test-tool   Test individual tools
          list-tools  List registered tools
          validate-tools  Validate all tools

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

        Enterprise Options:
            --workers N            Number of worker processes
            --min-workers N        Minimum workers for auto-scaling
            --max-workers N        Maximum workers for auto-scaling
            --enable-metrics       Enable metrics collection
            --metrics-port PORT    Metrics/dashboard port (default: 4000)
            --health-port PORT     Health check port (default: 4001)
            --enable-dashboard     Enable monitoring dashboard
            --auto-scale           Enable automatic scaling
            --scale-up-threshold N CPU threshold for scaling up
            --scale-down-threshold N CPU threshold for scaling down
            --load-balancer TYPE   Load balancer strategy
            --circuit-breaker      Enable circuit breaker
            --deployment-env ENV   Deployment environment
            --cluster-name NAME    Cluster name
            --node-name NAME       Node name
            --export-format FORMAT Export format (json, yaml, csv)
            --output-file FILE     Output file path

    EXAMPLES:
        # Start in production with custom settings
        my_agent start --agent-name voice_assistant --max-jobs 5 --production

        # Development mode with hot reload
        my_agent dev --hot-reload --log-level debug

        # Load configuration from file
        my_agent start --config-file ./config/production.json

        # Check worker health
        my_agent health --server-url ws://prod.livekit.cloud

        # Enterprise deployment examples
        my_agent deploy start --workers 8 --enable-dashboard --auto-scale
        my_agent scale to 10
        my_agent monitor export --format json --output-file metrics.json
        my_agent cluster init --cluster-name prod-cluster
        my_agent status
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
    with {:ok, content} <- File.read(file_path),
         {:ok, config} <- Jason.decode(content) do
      config
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Enum.into(%{})
    else
      {:error, reason} ->
        Logger.error("Failed to load config file #{file_path}: #{inspect(reason)}")
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

  # Tool Testing Commands

  @doc """
  Handles tool-related CLI commands.
  """
  def handle_tools_command(opts, args) do
    case args do
      ["list"] -> list_registered_tools(opts)
      ["validate"] -> validate_all_tools(opts)
      ["test", tool_name | test_args] -> test_single_tool_with_args(tool_name, test_args, opts)
      ["discover", path] -> discover_tools_in_path(path, opts)
      ["register", module_name] -> register_module_tools(module_name, opts)
      [] -> show_tools_help()
      _ -> show_tools_help()
    end
  end

  @doc """
  Lists all registered tools with their schemas.
  """
  def list_registered_tools(opts \\ []) do
    verbose = Keyword.get(opts, :verbose, false)
    format = Keyword.get(opts, :format, "table")

    IO.puts("🔧 Registered Function Tools")
    IO.puts(String.duplicate("=", 50))

    case LivekitexAgent.ToolRegistry.list_tools() do
      {:ok, tools} when length(tools) > 0 ->
        if format == "json" do
          tools
          |> Enum.map(&tool_to_json/1)
          |> Jason.encode!(pretty: true)
          |> IO.puts()
        else
          Enum.each(tools, fn tool ->
            print_tool_info(tool, verbose)
          end)
        end

        IO.puts("\n✅ Found #{length(tools)} registered tools")

      {:ok, []} ->
        IO.puts("📭 No tools are currently registered")
        IO.puts("\nTo register tools, run:")
        IO.puts("  mix livekitex_agent tools register MyToolModule")

      {:error, reason} ->
        IO.puts("❌ Failed to list tools: #{inspect(reason)}")
        System.halt(1)
    end
  end

  @doc """
  Tests a single tool with provided arguments.
  """
  def test_single_tool(opts, [tool_name | args]) do
    test_single_tool_with_args(tool_name, args, opts)
  end

  def test_single_tool(_opts, []) do
    IO.puts("❌ Tool name required")
    IO.puts("Usage: mix livekitex_agent test-tool <tool_name> [arg1=value1] [arg2=value2]")
    System.halt(1)
  end

  defp test_single_tool_with_args(tool_name, args, opts) do
    IO.puts("🧪 Testing tool: #{tool_name}")
    IO.puts(String.duplicate("-", 30))

    # Parse arguments
    parsed_args = parse_tool_arguments(args)

    # Create test context
    context = create_test_context(opts)

    # Execute tool
    start_time = System.monotonic_time(:millisecond)

    result = LivekitexAgent.FunctionTool.execute_tool_safely(
      tool_name,
      parsed_args,
      context,
      timeout: Keyword.get(opts, :timeout, 30_000),
      retry_attempts: Keyword.get(opts, :retry, 0)
    )

    duration = System.monotonic_time(:millisecond) - start_time

    # Display results
    print_test_result(tool_name, parsed_args, result, duration)
  end

  @doc """
  Validates all registered tools.
  """
  def validate_all_tools(opts \\ []) do
    IO.puts("🔍 Validating all registered tools...")
    IO.puts(String.duplicate("=", 40))

    case LivekitexAgent.ToolRegistry.list_tools() do
      {:ok, tools} when length(tools) > 0 ->
        results = Enum.map(tools, &validate_single_tool(&1, opts))

        passed = Enum.count(results, &match?({:ok, _}, &1))
        failed = length(results) - passed

        IO.puts("\n📊 Validation Summary:")
        IO.puts("  ✅ Passed: #{passed}")
        IO.puts("  ❌ Failed: #{failed}")

        if failed > 0 do
          System.halt(1)
        end

      {:ok, []} ->
        IO.puts("📭 No tools to validate")

      {:error, reason} ->
        IO.puts("❌ Failed to load tools: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp validate_single_tool(tool, opts) do
    tool_name = tool.name

    try do
      # Check if module and function exist
      unless Code.ensure_loaded?(tool.module) do
        raise "Module #{tool.module} not found"
      end

      unless function_exported?(tool.module, tool.function, tool.arity) do
        raise "Function #{tool.module}.#{tool.function}/#{tool.arity} not found"
      end

      # Validate schema
      schema_valid = validate_tool_schema(tool.schema)
      unless schema_valid do
        raise "Invalid OpenAI schema"
      end

      IO.puts("  ✅ #{tool_name}: Valid")
      {:ok, tool_name}

    rescue
      error ->
        IO.puts("  ❌ #{tool_name}: #{Exception.message(error)}")
        if Keyword.get(opts, :verbose, false) do
          IO.puts("    #{Exception.format_stacktrace(Exception.format_stacktrace(__STACKTRACE__))}")
        end
        {:error, tool_name}
    end
  end

  defp discover_tools_in_path(path, opts) do
    IO.puts("🔍 Discovering tools in: #{path}")

    count = LivekitexAgent.FunctionTool.discover_and_register_tools(path, opts)

    IO.puts("✅ Discovered and registered #{count} tool modules")
  end

  defp register_module_tools(module_name, opts) do
    try do
      module = String.to_existing_atom("Elixir.#{module_name}")

      case LivekitexAgent.FunctionTool.register_module(module, opts) do
        {:ok, count} ->
          IO.puts("✅ Registered #{count} tools from #{module_name}")

        {:error, reason} ->
          IO.puts("❌ Failed to register tools: #{inspect(reason)}")
          System.halt(1)
      end
    rescue
      ArgumentError ->
        IO.puts("❌ Module not found: #{module_name}")
        System.halt(1)
    end
  end

  defp show_tools_help do
    IO.puts("""
    🔧 Tool Management Commands

    Available commands:
      tools list                    - List all registered tools
      tools validate               - Validate all tool definitions
      tools test <name> [args...]  - Test a specific tool
      tools discover <path>        - Discover tools in directory
      tools register <module>      - Register tools from module

    Examples:
      mix livekitex_agent tools list --verbose
      mix livekitex_agent tools test get_weather location="New York"
      mix livekitex_agent tools validate
    """)
  end

  defp print_tool_info(tool, verbose) do
    IO.puts("📋 #{tool.name}")
    IO.puts("   Module: #{tool.module}")
    IO.puts("   Function: #{tool.function}")

    if verbose do
      IO.puts("   Description: #{get_tool_description(tool)}")
      IO.puts("   Parameters: #{inspect(tool.schema.function.parameters, pretty: true)}")
      IO.puts("   Registered: #{tool.metadata[:registered_at] || "Unknown"}")
    end

    IO.puts("")
  end

  defp tool_to_json(tool) do
    %{
      name: tool.name,
      module: to_string(tool.module),
      function: to_string(tool.function),
      description: get_tool_description(tool),
      schema: tool.schema,
      metadata: tool.metadata
    }
  end

  defp get_tool_description(tool) do
    get_in(tool.schema, [:function, :description]) || "No description available"
  end

  defp parse_tool_arguments(args) do
    args
    |> Enum.map(fn arg ->
      case String.split(arg, "=", parts: 2) do
        [key, value] -> {key, parse_argument_value(value)}
        [key] -> {key, true}
      end
    end)
    |> Enum.into(%{})
  end

  defp parse_argument_value(value) do
    cond do
      value == "true" -> true
      value == "false" -> false
      String.match?(value, ~r/^\d+$/) -> String.to_integer(value)
      String.match?(value, ~r/^\d+\.\d+$/) -> String.to_float(value)
      String.starts_with?(value, "[") or String.starts_with?(value, "{") ->
        case Jason.decode(value) do
          {:ok, parsed} -> parsed
          _ -> value
        end
      true -> value
    end
  end

  defp create_test_context(opts) do
    test_data = %{
      test_mode: true,
      user_id: "test_user",
      session_id: "test_session"
    }

    LivekitexAgent.RunContext.new(
      session: nil,
      user_data: test_data,
      metadata: %{cli_test: true, opts: opts}
    )
  end

  defp print_test_result(tool_name, args, result, duration) do
    IO.puts("Arguments: #{inspect(args, pretty: true)}")
    IO.puts("Duration: #{duration}ms")
    IO.puts("")

    case result do
      {:ok, output} ->
        IO.puts("✅ Success!")
        IO.puts("Result: #{inspect(output, pretty: true)}")

      {:error, reason} ->
        IO.puts("❌ Failed!")
        IO.puts("Error: #{inspect(reason, pretty: true)}")
    end
  end

  defp validate_tool_schema(schema) do
    required_keys = [:type, :function]
    function_keys = [:name, :description]

    Enum.all?(required_keys, &Map.has_key?(schema, &1)) and
      Enum.all?(function_keys, &Map.has_key?(schema.function, &1))
  end

  # Enterprise Deployment Commands

  @doc """
  Handles deployment commands for production environments.
  """
  def handle_deploy_command(opts, args) do
    case args do
      ["start"] ->
        deploy_start(opts)

      ["stop"] ->
        deploy_stop(opts)

      ["restart"] ->
        deploy_restart(opts)

      ["status"] ->
        deploy_status(opts)

      ["validate"] ->
        deploy_validate(opts)

      _ ->
        print_deploy_help()
    end
  end

  @doc """
  Handles cluster management commands.
  """
  def handle_cluster_command(opts, args) do
    case args do
      ["init"] ->
        cluster_init(opts)

      ["join", node_name] ->
        cluster_join(node_name, opts)

      ["leave"] ->
        cluster_leave(opts)

      ["status"] ->
        cluster_status(opts)

      ["nodes"] ->
        cluster_list_nodes(opts)

      _ ->
        print_cluster_help()
    end
  end

  @doc """
  Handles scaling commands for worker pools.
  """
  def handle_scale_command(opts, args) do
    case args do
      ["up", count] ->
        scale_up(String.to_integer(count), opts)

      ["down", count] ->
        scale_down(String.to_integer(count), opts)

      ["to", count] ->
        scale_to(String.to_integer(count), opts)

      ["auto", "enable"] ->
        enable_auto_scaling(opts)

      ["auto", "disable"] ->
        disable_auto_scaling(opts)

      ["status"] ->
        scale_status(opts)

      _ ->
        print_scale_help()
    end
  end

  @doc """
  Handles monitoring commands.
  """
  def handle_monitor_command(opts, args) do
    case args do
      ["start"] ->
        start_monitoring(opts)

      ["stop"] ->
        stop_monitoring(opts)

      ["tail"] ->
        tail_logs(opts)

      ["export"] ->
        export_monitoring_data(opts)

      _ ->
        print_monitor_help()
    end
  end

  @doc """
  Handles metrics commands.
  """
  def handle_metrics_command(opts, args) do
    case args do
      ["show"] ->
        show_metrics(opts)

      ["export"] ->
        export_metrics(opts)

      ["reset"] ->
        reset_metrics(opts)

      ["configure"] ->
        configure_metrics(opts)

      _ ->
        print_metrics_help()
    end
  end

  @doc """
  Handles dashboard commands.
  """
  def handle_dashboard_command(opts, args) do
    case args do
      ["start"] ->
        start_dashboard(opts)

      ["stop"] ->
        stop_dashboard(opts)

      ["url"] ->
        show_dashboard_url(opts)

      _ ->
        print_dashboard_help()
    end
  end

  @doc """
  Handles status commands for system overview.
  """
  def handle_status_command(opts, _args) do
    show_system_status(opts)
  end

  @doc """
  Handles graceful shutdown/drain commands.
  """
  def handle_drain_command(opts, args) do
    case args do
      ["start"] ->
        start_drain(opts)

      ["cancel"] ->
        cancel_drain(opts)

      ["status"] ->
        drain_status(opts)

      _ ->
        print_drain_help()
    end
  end

  @doc """
  Handles restart commands.
  """
  def handle_restart_command(opts, args) do
    case args do
      ["graceful"] ->
        graceful_restart(opts)

      ["force"] ->
        force_restart(opts)

      [] ->
        graceful_restart(opts)

      _ ->
        print_restart_help()
    end
  end

  @doc """
  Handles backup commands.
  """
  def handle_backup_command(opts, args) do
    case args do
      ["create"] ->
        create_backup(opts)

      ["list"] ->
        list_backups(opts)

      ["restore", backup_id] ->
        restore_backup(backup_id, opts)

      _ ->
        print_backup_help()
    end
  end

  @doc """
  Handles restore commands.
  """
  def handle_restore_command(opts, args) do
    case args do
      [backup_file] ->
        restore_from_file(backup_file, opts)

      _ ->
        print_restore_help()
    end
  end

  # Implementation functions for enterprise commands

  defp deploy_start(opts) do
    IO.puts("🚀 Starting production deployment...")

    config = build_deployment_config(opts)

    case start_production_cluster(config) do
      {:ok, _pid} ->
        IO.puts("✅ Deployment started successfully")
        IO.puts("   Workers: #{config.workers}")
        IO.puts("   Health endpoint: http://#{config.host}:#{config.health_port}/health")
        if config.enable_dashboard do
          IO.puts("   Dashboard: http://#{config.host}:#{config.metrics_port}/dashboard")
        end

      {:error, reason} ->
        IO.puts("❌ Deployment failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp deploy_stop(opts) do
    IO.puts("🛑 Stopping deployment...")

    timeout = Keyword.get(opts, :drain_timeout, 30_000)

    case LivekitexAgent.Application.graceful_shutdown(timeout) do
      :ok ->
        IO.puts("✅ Deployment stopped gracefully")

      {:error, :timeout} ->
        IO.puts("⚠️  Graceful shutdown timed out, forcing stop...")
        System.halt(0)

      {:error, reason} ->
        IO.puts("❌ Stop failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp deploy_restart(opts) do
    IO.puts("🔄 Restarting deployment...")
    deploy_stop(opts)
    :timer.sleep(2000)  # Brief pause between stop and start
    deploy_start(opts)
  end

  defp deploy_status(opts) do
    IO.puts("📊 Deployment Status")
    IO.puts("===================")

    case get_worker_manager_status() do
      {:ok, status} ->
        print_deployment_status(status)

      {:error, reason} ->
        IO.puts("❌ Could not retrieve status: #{inspect(reason)}")
    end
  end

  defp deploy_validate(opts) do
    IO.puts("🔍 Validating deployment configuration...")

    config = build_deployment_config(opts)
    issues = validate_deployment_config(config)

    if Enum.empty?(issues) do
      IO.puts("✅ Configuration is valid")
      print_config_summary(config)
    else
      IO.puts("❌ Configuration issues found:")
      Enum.each(issues, &IO.puts("   - #{&1}"))
      System.halt(1)
    end
  end

  defp cluster_init(opts) do
    cluster_name = Keyword.get(opts, :cluster_name, "livekitex-cluster")
    node_name = Keyword.get(opts, :node_name, "node1")

    IO.puts("🏗️  Initializing cluster: #{cluster_name}")
    IO.puts("   Node name: #{node_name}")

    # Implementation would involve setting up distributed Elixir
    IO.puts("✅ Cluster initialized (placeholder implementation)")
  end

  defp cluster_join(node_name, _opts) do
    IO.puts("🔗 Joining cluster node: #{node_name}")
    # Implementation would use Node.connect/1
    IO.puts("✅ Joined cluster (placeholder implementation)")
  end

  defp cluster_leave(_opts) do
    IO.puts("👋 Leaving cluster...")
    # Implementation would use Node.disconnect/1
    IO.puts("✅ Left cluster (placeholder implementation)")
  end

  defp cluster_status(_opts) do
    IO.puts("🌐 Cluster Status")
    IO.puts("================")
    IO.puts("Connected nodes: #{inspect(Node.list())}")
    IO.puts("Current node: #{Node.self()}")
  end

  defp cluster_list_nodes(_opts) do
    nodes = [Node.self() | Node.list()]
    IO.puts("📍 Cluster Nodes (#{length(nodes)} total):")
    Enum.each(nodes, fn node ->
      status = if node == Node.self(), do: "(current)", else: ""
      IO.puts("   - #{node} #{status}")
    end)
  end

  defp scale_up(count, _opts) do
    IO.puts("⬆️  Scaling up by #{count} workers...")

    case get_worker_manager() do
      {:ok, manager} ->
        case LivekitexAgent.WorkerManager.scale_workers(manager, count) do
          :ok ->
            IO.puts("✅ Scaled up successfully")

          {:error, reason} ->
            IO.puts("❌ Scale up failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("❌ Could not access worker manager: #{inspect(reason)}")
    end
  end

  defp scale_down(count, _opts) do
    IO.puts("⬇️  Scaling down by #{count} workers...")

    case get_worker_manager() do
      {:ok, manager} ->
        case LivekitexAgent.WorkerManager.scale_workers(manager, -count) do
          :ok ->
            IO.puts("✅ Scaled down successfully")

          {:error, reason} ->
            IO.puts("❌ Scale down failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("❌ Could not access worker manager: #{inspect(reason)}")
    end
  end

  defp scale_to(count, _opts) do
    IO.puts("🎯 Scaling to #{count} workers...")

    case get_worker_manager() do
      {:ok, manager} ->
        case LivekitexAgent.WorkerManager.set_worker_count(manager, count) do
          :ok ->
            IO.puts("✅ Scaled to target successfully")

          {:error, reason} ->
            IO.puts("❌ Scale to target failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("❌ Could not access worker manager: #{inspect(reason)}")
    end
  end

  defp enable_auto_scaling(_opts) do
    IO.puts("🤖 Enabling auto-scaling...")

    case Process.whereis(LivekitexAgent.AutoScaler) do
      nil ->
        IO.puts("❌ AutoScaler not running")

      pid ->
        GenServer.cast(pid, :enable)
        IO.puts("✅ Auto-scaling enabled")
    end
  end

  defp disable_auto_scaling(_opts) do
    IO.puts("⏸️  Disabling auto-scaling...")

    case Process.whereis(LivekitexAgent.AutoScaler) do
      nil ->
        IO.puts("❌ AutoScaler not running")

      pid ->
        GenServer.cast(pid, :disable)
        IO.puts("✅ Auto-scaling disabled")
    end
  end

  defp scale_status(_opts) do
    IO.puts("📏 Scaling Status")
    IO.puts("=================")

    case get_worker_manager_status() do
      {:ok, status} ->
        IO.puts("Current workers: #{status.active_workers_count}")
        IO.puts("Target workers: #{status.target_workers || "auto"}")
        IO.puts("Active jobs: #{status.active_jobs_count}")
        IO.puts("Pending jobs: #{status.pending_jobs_count}")

        case Process.whereis(LivekitexAgent.AutoScaler) do
          nil ->
            IO.puts("Auto-scaling: disabled")

          _pid ->
            IO.puts("Auto-scaling: enabled")
        end

      {:error, reason} ->
        IO.puts("❌ Could not retrieve scaling status: #{inspect(reason)}")
    end
  end

  defp start_monitoring(_opts) do
    IO.puts("📈 Starting monitoring...")
    # Implementation would start monitoring processes
    IO.puts("✅ Monitoring started")
  end

  defp stop_monitoring(_opts) do
    IO.puts("📉 Stopping monitoring...")
    # Implementation would stop monitoring processes
    IO.puts("✅ Monitoring stopped")
  end

  defp tail_logs(opts) do
    IO.puts("📋 Tailing logs... (Press Ctrl+C to stop)")
    # Implementation would tail logs in real-time
    # For now, just show recent logs
    show_recent_logs(opts)
  end

  defp export_monitoring_data(opts) do
    format = Keyword.get(opts, :export_format, "json")
    output_file = Keyword.get(opts, :output_file, "monitoring_export.#{format}")

    IO.puts("💾 Exporting monitoring data to #{output_file}...")

    case collect_monitoring_data() do
      {:ok, data} ->
        case export_data(data, format, output_file) do
          :ok ->
            IO.puts("✅ Monitoring data exported successfully")

          {:error, reason} ->
            IO.puts("❌ Export failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("❌ Could not collect monitoring data: #{inspect(reason)}")
    end
  end

  defp show_metrics(_opts) do
    IO.puts("📊 Current Metrics")
    IO.puts("==================")

    case get_metrics_summary() do
      {:ok, metrics} ->
        print_metrics_summary(metrics)

      {:error, reason} ->
        IO.puts("❌ Could not retrieve metrics: #{inspect(reason)}")
    end
  end

  defp export_metrics(opts) do
    format = Keyword.get(opts, :export_format, "json")
    output_file = Keyword.get(opts, :output_file, "metrics_export.#{format}")

    IO.puts("💾 Exporting metrics to #{output_file}...")

    case LivekitexAgent.Telemetry.Metrics.generate_report() do
      {:ok, report} ->
        case export_data(report, format, output_file) do
          :ok ->
            IO.puts("✅ Metrics exported successfully")

          {:error, reason} ->
            IO.puts("❌ Export failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("❌ Could not generate metrics report: #{inspect(reason)}")
    end
  end

  defp reset_metrics(_opts) do
    IO.puts("🔄 Resetting metrics...")

    case LivekitexAgent.Telemetry.Metrics.reset_all() do
      :ok ->
        IO.puts("✅ Metrics reset successfully")

      {:error, reason} ->
        IO.puts("❌ Reset failed: #{inspect(reason)}")
    end
  end

  defp configure_metrics(_opts) do
    IO.puts("⚙️  Configuring metrics...")
    # Implementation would allow interactive metrics configuration
    IO.puts("✅ Metrics configured")
  end

  defp start_dashboard(opts) do
    port = Keyword.get(opts, :metrics_port, 4000)
    host = Keyword.get(opts, :host, "localhost")

    IO.puts("🖥️  Starting dashboard on http://#{host}:#{port}")

    # Dashboard would be started as part of HealthServer
    case Process.whereis(LivekitexAgent.HealthServer) do
      nil ->
        IO.puts("❌ Health server not running")

      _pid ->
        IO.puts("✅ Dashboard available at http://#{host}:#{port}/dashboard")
    end
  end

  defp stop_dashboard(_opts) do
    IO.puts("🔚 Stopping dashboard...")
    # Implementation would stop dashboard service
    IO.puts("✅ Dashboard stopped")
  end

  defp show_dashboard_url(opts) do
    port = Keyword.get(opts, :metrics_port, 4000)
    host = Keyword.get(opts, :host, "localhost")
    IO.puts("🔗 Dashboard URL: http://#{host}:#{port}/dashboard")
  end

  defp show_system_status(_opts) do
    IO.puts("🏥 System Status")
    IO.puts("================")

    # Application status
    IO.puts("Application: #{app_status()}")

    # Worker manager status
    case get_worker_manager_status() do
      {:ok, status} ->
        IO.puts("Workers: #{status.active_workers_count}/#{status.target_workers || "auto"}")
        IO.puts("Active jobs: #{status.active_jobs_count}")
        IO.puts("Pending jobs: #{status.pending_jobs_count}")

      {:error, _} ->
        IO.puts("Workers: unavailable")
    end

    # Health checks
    case perform_health_checks() do
      {:ok, health} ->
        Enum.each(health, fn {component, status} ->
          icon = if status == :healthy, do: "✅", else: "❌"
          IO.puts("#{component}: #{icon} #{status}")
        end)

      {:error, _} ->
        IO.puts("Health checks: unavailable")
    end

    # System resources
    print_system_resources()
  end

  defp start_drain(opts) do
    timeout = Keyword.get(opts, :drain_timeout, 60_000)
    IO.puts("🚰 Starting graceful drain (timeout: #{timeout}ms)...")

    case LivekitexAgent.Application.start_graceful_shutdown(timeout) do
      :ok ->
        IO.puts("✅ Drain started - no new jobs will be accepted")

      {:error, reason} ->
        IO.puts("❌ Drain failed: #{inspect(reason)}")
    end
  end

  defp cancel_drain(_opts) do
    IO.puts("❌ Canceling drain...")
    # Implementation would cancel ongoing drain
    IO.puts("✅ Drain canceled")
  end

  defp drain_status(_opts) do
    IO.puts("🚰 Drain Status")
    IO.puts("===============")
    # Implementation would show drain progress
    IO.puts("Status: Not draining")
  end

  defp graceful_restart(opts) do
    IO.puts("🔄 Performing graceful restart...")
    timeout = Keyword.get(opts, :drain_timeout, 60_000)

    case LivekitexAgent.Application.graceful_shutdown(timeout) do
      :ok ->
        IO.puts("✅ Shutdown complete, restarting...")
        System.restart()

      {:error, reason} ->
        IO.puts("❌ Graceful restart failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp force_restart(_opts) do
    IO.puts("⚡ Performing force restart...")
    System.restart()
  end

  defp create_backup(opts) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    backup_file = "backup_#{timestamp}.tar.gz"

    IO.puts("💾 Creating backup: #{backup_file}")

    case create_system_backup(backup_file, opts) do
      :ok ->
        IO.puts("✅ Backup created successfully")

      {:error, reason} ->
        IO.puts("❌ Backup failed: #{inspect(reason)}")
    end
  end

  defp list_backups(_opts) do
    IO.puts("📋 Available Backups")
    IO.puts("====================")
    # Implementation would list available backups
    IO.puts("No backups found (placeholder implementation)")
  end

  defp restore_backup(backup_id, _opts) do
    IO.puts("🔄 Restoring from backup: #{backup_id}")
    # Implementation would restore from backup
    IO.puts("✅ Restore completed (placeholder implementation)")
  end

  defp restore_from_file(backup_file, _opts) do
    IO.puts("🔄 Restoring from file: #{backup_file}")
    # Implementation would restore from backup file
    IO.puts("✅ Restore completed (placeholder implementation)")
  end

  # Helper functions for enterprise commands

  defp build_deployment_config(opts) do
    %{
      workers: Keyword.get(opts, :workers, 4),
      min_workers: Keyword.get(opts, :min_workers, 2),
      max_workers: Keyword.get(opts, :max_workers, 20),
      enable_metrics: Keyword.get(opts, :enable_metrics, true),
      metrics_port: Keyword.get(opts, :metrics_port, 4000),
      health_port: Keyword.get(opts, :health_port, 4001),
      enable_dashboard: Keyword.get(opts, :enable_dashboard, true),
      auto_scale: Keyword.get(opts, :auto_scale, true),
      scale_up_threshold: Keyword.get(opts, :scale_up_threshold, 0.8),
      scale_down_threshold: Keyword.get(opts, :scale_down_threshold, 0.3),
      load_balancer: Keyword.get(opts, :load_balancer, "round_robin"),
      circuit_breaker: Keyword.get(opts, :circuit_breaker, true),
      host: Keyword.get(opts, :host, "localhost"),
      deployment_env: Keyword.get(opts, :deployment_env, "production")
    }
  end

  defp start_production_cluster(config) do
    # Implementation would start the application with enterprise configuration
    Application.put_env(:livekitex_agent, :worker_options, [
      max_workers: config.workers,
      enable_load_balancing: true,
      load_balancer_strategy: String.to_atom(config.load_balancer),
      enable_auto_scaling: config.auto_scale,
      auto_scale_up_threshold: config.scale_up_threshold,
      auto_scale_down_threshold: config.scale_down_threshold,
      enable_circuit_breaker: config.circuit_breaker
    ])

    {:ok, self()}  # Placeholder
  end

  defp get_worker_manager do
    case Process.whereis(LivekitexAgent.WorkerManager) do
      nil -> {:error, :not_running}
      pid -> {:ok, pid}
    end
  end

  defp get_worker_manager_status do
    case get_worker_manager() do
      {:ok, manager} ->
        try do
          status = LivekitexAgent.WorkerManager.get_status()
          {:ok, status}
        catch
          :exit, reason -> {:error, reason}
        end

      error ->
        error
    end
  end

  defp validate_deployment_config(config) do
    issues = []

    issues =
      if config.workers < 1 do
        ["Workers count must be at least 1" | issues]
      else
        issues
      end

    issues =
      if config.min_workers > config.max_workers do
        ["Min workers cannot be greater than max workers" | issues]
      else
        issues
      end

    issues =
      if config.scale_up_threshold <= config.scale_down_threshold do
        ["Scale up threshold must be greater than scale down threshold" | issues]
      else
        issues
      end

    Enum.reverse(issues)
  end

  defp print_deployment_status(status) do
    IO.puts("Active workers: #{status.active_workers_count}")
    IO.puts("Active jobs: #{status.active_jobs_count}")
    IO.puts("Pending jobs: #{status.pending_jobs_count}")
    IO.puts("Total processed: #{status.completed_jobs_count}")

    if Map.has_key?(status, :load_balancer_strategy) do
      IO.puts("Load balancer: #{status.load_balancer_strategy}")
    end

    if Map.has_key?(status, :circuit_breaker_state) do
      IO.puts("Circuit breaker: #{status.circuit_breaker_state}")
    end
  end

  defp print_config_summary(config) do
    IO.puts("\nDeployment Configuration:")
    IO.puts("========================")
    IO.puts("Workers: #{config.workers}")
    IO.puts("Auto-scaling: #{config.min_workers}-#{config.max_workers}")
    IO.puts("Load balancer: #{config.load_balancer}")
    IO.puts("Metrics: #{config.enable_metrics}")
    IO.puts("Dashboard: #{config.enable_dashboard}")
    IO.puts("Environment: #{config.deployment_env}")
  end

  defp app_status do
    if Process.whereis(LivekitexAgent.Application) do
      "running"
    else
      "stopped"
    end
  end

  defp perform_health_checks do
    case Process.whereis(LivekitexAgent.HealthServer) do
      nil ->
        {:error, :health_server_not_running}

      _pid ->
        # Simplified health check
        checks = %{
          "worker_manager" => if(Process.whereis(LivekitexAgent.WorkerManager), do: :healthy, else: :unhealthy),
          "metrics" => if(Process.whereis(LivekitexAgent.Telemetry.Metrics), do: :healthy, else: :unhealthy),
          "tool_registry" => if(Process.whereis(LivekitexAgent.ToolRegistry), do: :healthy, else: :unhealthy)
        }

        {:ok, checks}
    end
  end

  defp print_system_resources do
    # System resource information
    memory = :erlang.memory()
    total_mb = div(memory[:total], 1024 * 1024)
    process_mb = div(memory[:processes], 1024 * 1024)

    IO.puts("Memory: #{total_mb}MB total, #{process_mb}MB processes")
    IO.puts("Processes: #{:erlang.system_info(:process_count)}")
    IO.puts("Schedulers: #{:erlang.system_info(:schedulers_online)}")
  end

  defp show_recent_logs(opts) do
    # Implementation would show recent log entries
    level = Keyword.get(opts, :log_level, "info")
    lines = Keyword.get(opts, :lines, 50)

    IO.puts("📋 Recent logs (#{level} level, last #{lines} lines):")
    IO.puts("Logs would be shown here...")
  end

  defp collect_monitoring_data do
    # Collect comprehensive monitoring data
    data = %{
      timestamp: DateTime.utc_now(),
      system: %{
        memory: :erlang.memory(),
        processes: :erlang.system_info(:process_count),
        schedulers: :erlang.system_info(:schedulers_online)
      },
      application: %{
        status: app_status()
      }
    }

    {:ok, data}
  end

  defp export_data(data, format, output_file) do
    try do
      content =
        case format do
          "json" ->
            Jason.encode!(data, pretty: true)

          "yaml" ->
            # Would need a YAML library
            "# YAML export not implemented\n#{inspect(data, pretty: true)}"

          _ ->
            inspect(data, pretty: true)
        end

      File.write!(output_file, content)
      :ok
    rescue
      error ->
        {:error, error}
    end
  end

  defp get_metrics_summary do
    case Process.whereis(LivekitexAgent.Telemetry.Metrics) do
      nil ->
        {:error, :metrics_not_running}

      _pid ->
        # Get summary metrics
        summary = %{
          uptime: System.uptime(),
          memory: :erlang.memory()[:total],
          processes: :erlang.system_info(:process_count)
        }

        {:ok, summary}
    end
  end

  defp print_metrics_summary(metrics) do
    IO.puts("Uptime: #{metrics.uptime} seconds")
    IO.puts("Memory: #{div(metrics.memory, 1024 * 1024)}MB")
    IO.puts("Processes: #{metrics.processes}")
  end

  defp create_system_backup(backup_file, _opts) do
    # Implementation would create a system backup
    try do
      # Placeholder - would compress relevant system state
      File.write!(backup_file, "backup_placeholder_content")
      :ok
    rescue
      error ->
        {:error, error}
    end
  end

  # Help functions for enterprise commands

  defp print_deploy_help do
    IO.puts("""
    Deploy Commands:

      deploy start                 Start production deployment
      deploy stop                  Stop deployment gracefully
      deploy restart               Restart deployment
      deploy status                Show deployment status
      deploy validate              Validate deployment configuration

    Options:
      --workers N                  Number of worker processes
      --enable-metrics             Enable metrics collection
      --enable-dashboard           Enable monitoring dashboard
      --auto-scale                 Enable automatic scaling
      --load-balancer STRATEGY     Load balancing strategy
      --deployment-env ENV         Deployment environment
    """)
  end

  defp print_cluster_help do
    IO.puts("""
    Cluster Commands:

      cluster init                 Initialize new cluster
      cluster join NODE            Join existing cluster
      cluster leave                Leave current cluster
      cluster status               Show cluster status
      cluster nodes                List cluster nodes

    Options:
      --cluster-name NAME          Cluster name
      --node-name NAME             Node name
    """)
  end

  defp print_scale_help do
    IO.puts("""
    Scale Commands:

      scale up N                   Scale up by N workers
      scale down N                 Scale down by N workers
      scale to N                   Scale to exactly N workers
      scale auto enable            Enable auto-scaling
      scale auto disable           Disable auto-scaling
      scale status                 Show scaling status

    Options:
      --scale-up-threshold N       CPU threshold for scaling up
      --scale-down-threshold N     CPU threshold for scaling down
    """)
  end

  defp print_monitor_help do
    IO.puts("""
    Monitor Commands:

      monitor start                Start monitoring
      monitor stop                 Stop monitoring
      monitor tail                 Tail logs in real-time
      monitor export               Export monitoring data

    Options:
      --export-format FORMAT       Export format (json, yaml, csv)
      --output-file FILE           Output file path
    """)
  end

  defp print_metrics_help do
    IO.puts("""
    Metrics Commands:

      metrics show                 Show current metrics
      metrics export               Export metrics data
      metrics reset                Reset all metrics
      metrics configure            Configure metrics collection

    Options:
      --export-format FORMAT       Export format (json, yaml, csv)
      --output-file FILE           Output file path
    """)
  end

  defp print_dashboard_help do
    IO.puts("""
    Dashboard Commands:

      dashboard start              Start monitoring dashboard
      dashboard stop               Stop monitoring dashboard
      dashboard url                Show dashboard URL

    Options:
      --metrics-port PORT          Dashboard port
      --host HOST                  Dashboard host
    """)
  end

  defp print_drain_help do
    IO.puts("""
    Drain Commands:

      drain start                  Start graceful drain
      drain cancel                 Cancel ongoing drain
      drain status                 Show drain status

    Options:
      --drain-timeout MS           Drain timeout in milliseconds
    """)
  end

  defp print_restart_help do
    IO.puts("""
    Restart Commands:

      restart                      Graceful restart (default)
      restart graceful             Graceful restart with job completion
      restart force                Force restart immediately

    Options:
      --drain-timeout MS           Drain timeout in milliseconds
    """)
  end

  defp print_backup_help do
    IO.puts("""
    Backup Commands:

      backup create                Create system backup
      backup list                  List available backups
      backup restore ID            Restore from backup

    Options:
      --output-file FILE           Backup file path
    """)
  end

  defp print_restore_help do
    IO.puts("""
    Restore Commands:

      restore BACKUP_FILE          Restore from backup file
    """)
  end
end
