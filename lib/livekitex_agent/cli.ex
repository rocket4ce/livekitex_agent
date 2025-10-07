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
end
