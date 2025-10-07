defmodule LivekitexAgent.Example do
  @moduledoc """
  Example usage of LivekitexAgent functionality.

  This module demonstrates how to:
  - Create and configure an agent
  - Start an agent session
  - Handle job contexts
  - Use function tools
  - Configure and start workers
  """

  require Logger

  @doc """
  Example of creating a simple voice agent.
  """
  def create_simple_agent do
    # Create an agent with basic configuration
    case LivekitexAgent.Agent.new(
           instructions: "You are a helpful voice assistant. Be concise and friendly.",
           tools: [:get_weather, :add_numbers, :search_web],
           agent_id: "simple_voice_agent_001"
         ) do
      {:ok, agent} ->
        Logger.info("Created agent: #{agent.agent_id}")
        {:ok, agent}

      {:error, reason} ->
        Logger.error("Failed to create agent: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example of starting an agent session.
  """
  def start_agent_session(agent) do
    # Configure session options
    session_opts = [
      agent: agent,
      # Would be actual LLM client in production
      llm_client: nil,
      # Would be actual TTS client in production
      tts_client: nil,
      # Would be actual STT client in production
      stt_client: nil,
      event_callbacks: %{
        session_started: &handle_session_started/2,
        text_received: &handle_text_received/2,
        speaking_started: &handle_speaking_started/2
      }
    ]

    case LivekitexAgent.AgentSession.start_link(session_opts) do
      {:ok, session_pid} ->
        Logger.info("Agent session started: #{inspect(session_pid)}")

        # Example: Process some text
        LivekitexAgent.AgentSession.process_text(
          session_pid,
          "What's the weather like in New York?"
        )

        session_pid

      {:error, reason} ->
        Logger.error("Failed to start session: #{inspect(reason)}")
        nil
    end
  end

  @doc """
  Example of creating a job context.
  """
  def create_job_example do
    job_opts = [
      job_id: "example_job_123",
      room: %{
        name: "example_room",
        token: "example_token"
      },
      callbacks: %{
        on_participant_connected: &handle_participant_connected/1,
        on_job_started: &handle_job_started/1,
        on_shutdown: &handle_shutdown/1
      },
      metadata: %{
        created_by: "example_system",
        priority: :normal
      }
    ]

    case LivekitexAgent.JobContext.start_link(job_opts) do
      {:ok, job_pid} ->
        Logger.info("Job context started")

        # Example: Add participants
        LivekitexAgent.JobContext.add_participant(job_pid, "user_001", %{
          name: "Alice",
          role: "user"
        })

        # Example: Start a task
        LivekitexAgent.JobContext.start_task(job_pid, "background_task", fn ->
          Logger.info("Background task running...")
          :timer.sleep(5000)
          Logger.info("Background task completed")
        end)

        job_pid

      {:error, reason} ->
        Logger.error("Failed to start job context: #{inspect(reason)}")
        nil
    end
  end

  @doc """
  Example of using function tools.
  """
  def demonstrate_tools do
    # Create a run context
    context =
      LivekitexAgent.RunContext.new(
        session: nil,
        function_call: %{name: "get_weather", arguments: %{"location" => "Madrid"}},
        user_data: %{user_id: "user_123", language: "es"}
      )

    # Execute weather tool
    case LivekitexAgent.FunctionTool.execute_tool("get_weather", %{"location" => "Madrid"}) do
      {:ok, result} ->
        Logger.info("Weather result: #{result}")

      {:error, reason} ->
        Logger.error("Tool execution failed: #{inspect(reason)}")
    end

    # Execute math tool
    case LivekitexAgent.FunctionTool.execute_tool("add_numbers", %{"a" => 15, "b" => 27}) do
      {:ok, result} ->
        Logger.info("Math result: #{result}")

      {:error, reason} ->
        Logger.error("Math tool failed: #{inspect(reason)}")
    end

    # Execute search tool with context
    case LivekitexAgent.FunctionTool.execute_tool(
           "search_web",
           %{"query" => "Elixir programming"},
           context
         ) do
      {:ok, result} ->
        Logger.info("Search result: #{result}")

      {:error, reason} ->
        Logger.error("Search tool failed: #{inspect(reason)}")
    end
  end

  @doc """
  Example of configuring and starting a worker.
  """
  def start_worker_example do
    # Define the entry point for jobs
    entry_point = fn job_context ->
      Logger.info("Job started: #{job_context.job_id}")

      # Create agent for this job
      agent = create_simple_agent()

      # Start agent session
      session_pid = start_agent_session(agent)

      if session_pid do
        # Keep the session running for the job
        Process.monitor(session_pid)

        receive do
          {:DOWN, _ref, :process, ^session_pid, reason} ->
            Logger.info("Session ended: #{inspect(reason)}")
        end
      end

      Logger.info("Job completed: #{job_context.job_id}")
    end

    # Create worker options
    worker_options =
      LivekitexAgent.WorkerOptions.new(
        entry_point: entry_point,
        agent_name: "example_agent",
        server_url: "ws://localhost:7880",
        api_key: "dev_api_key",
        api_secret: "dev_api_secret",
        max_concurrent_jobs: 3,
        worker_type: :voice_agent,
        log_level: :info
      )

    case LivekitexAgent.WorkerOptions.validate(worker_options) do
      {:ok, validated_options} ->
        Logger.info("Worker options validated")

        # In a real scenario, this would start the worker supervisor
        Logger.info("Would start worker with options: #{validated_options.agent_name}")
        {:ok, validated_options}

      {:error, reason} ->
        Logger.error("Invalid worker options: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Complete example that ties everything together.
  """
  def run_complete_example do
    Logger.info("Starting complete LivekitexAgent example")

    # 1. Create agent
    agent = create_simple_agent()

    # 2. Start session
    session_pid = start_agent_session(agent)

    # 3. Create job context
    job_pid = create_job_example()

    # 4. Demonstrate tools
    demonstrate_tools()

    # 5. Configure worker
    case start_worker_example() do
      {:ok, worker_options} ->
        Logger.info("Example completed successfully")

        # Clean up
        if session_pid, do: LivekitexAgent.AgentSession.stop(session_pid)
        if job_pid, do: LivekitexAgent.JobContext.shutdown(job_pid)

        {:ok,
         %{
           agent: agent,
           session_pid: session_pid,
           job_pid: job_pid,
           worker_options: worker_options
         }}

      {:error, reason} ->
        Logger.error("Example failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Minimal example to start an AgentSession with Realtime WebSocket client.

  Configure env vars before running:
    - OAI_API_KEY (or pass in opts)
  """
  def start_realtime_example(opts \\ []) do
    require Logger

    url =
      Keyword.get(
        opts,
        :url,
        System.get_env("OAI_REALTIME_URL") ||
          "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17"
      )

    api_key =
      Keyword.get(
        opts,
        :api_key,
        System.get_env("OPENAI_API_KEY") || System.get_env("OAI_API_KEY")
      )

    agent =
      LivekitexAgent.Agent.new(
        instructions: "You are a helpful, concise, real-time voice assistant.",
        tools: []
      )

    rt_cfg =
      %{url: url, api_key: api_key, log_frames: true}

    case LivekitexAgent.AgentSession.start_link(agent: agent, realtime_config: rt_cfg) do
      {:ok, pid} ->
        Logger.info("Realtime AgentSession started: #{inspect(pid)}")
        pid

      {:error, reason} ->
        Logger.error("Failed to start realtime session: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Event handlers

  defp handle_session_started(:session_started, data) do
    Logger.info("Session started event: #{inspect(data)}")
  end

  defp handle_text_received(:text_received, data) do
    Logger.info("Text received event: #{inspect(data)}")
  end

  defp handle_speaking_started(:speaking_started, data) do
    Logger.info("Speaking started event: #{inspect(data)}")
  end

  defp handle_participant_connected({participant_id, participant_info}) do
    Logger.info("Participant connected: #{participant_id} - #{inspect(participant_info)}")
  end

  defp handle_job_started(job_context) do
    Logger.info("Job started: #{job_context.job_id}")
  end

  defp handle_shutdown(reason) do
    Logger.info("Job shutdown: #{inspect(reason)}")
  end
end
