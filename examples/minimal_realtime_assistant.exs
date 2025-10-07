#!/usr/bin/env elixir

# Minimal Real-time Assistant Example
#
# This example demonstrates the core functionality of a LiveKit voice agent
# with conversation capabilities using OpenAI providers for LLM, STT, and TTS.
#
# Usage:
#   export OPENAI_API_KEY="your-key-here"
#   export LIVEKIT_URL="wss://your-livekit-server.com"
#   export LIVEKIT_API_KEY="your-api-key"
#   export LIVEKIT_API_SECRET="your-api-secret"
#   elixir examples/minimal_realtime_assistant.exs

Mix.install([
  {:livekitex_agent, path: ".."}
])

defmodule MinimalRealtimeAssistant do
  @moduledoc """
  A minimal real-time voice assistant example that demonstrates:
  - Agent configuration with OpenAI providers
  - Session event handling
  - Real-time voice interaction patterns
  - Basic conversation flow
  """

  alias LivekitexAgent.{Agent, AgentSession, WorkerOptions, WorkerManager}
  require Logger

  def run do
    Logger.info("Starting Minimal Real-time Assistant...")

    # Configure worker options
    worker_options = %WorkerOptions{
      agent_name: "minimal-assistant",
      worker_type: :voice_agent,
      server_url: System.get_env("LIVEKIT_URL"),
      api_key: System.get_env("LIVEKIT_API_KEY"),
      api_secret: System.get_env("LIVEKIT_API_SECRET"),
      timeout: 60_000,
      max_concurrent_jobs: 10,
      entry_point: &handle_job/1
    }

    Logger.info("Waiting for LiveKit room connections...")

    # Start the worker manager
    WorkerManager.start_worker(worker_options)
  end

  def handle_job(job_context) do
    Logger.info("New job assigned: #{inspect(job_context)}")

    # Create agent session configuration
    session_config = %{
      instructions: """
      You are a helpful voice assistant. Keep your responses concise and conversational.
      You can help with general questions and have friendly conversations.
      """,
      metadata: %{
        example: "minimal_realtime_assistant",
        version: "1.0"
      }
    }

    # Start the agent session
    {:ok, session} = AgentSession.create(session_config)

    # Register event callbacks
    register_callbacks(session)

    # Keep the session running
    AgentSession.start(session)
  end

  defp register_callbacks(session) do
    # Session lifecycle events
    AgentSession.on_event(session, :session_started, &handle_session_started/1)
    AgentSession.on_event(session, :session_stopped, &handle_session_stopped/1)

    # Speech recognition events
    AgentSession.on_event(session, :stt_result, &handle_stt_result/2)
    AgentSession.on_event(session, :text_received, &handle_text_received/2)

    # Response events
    AgentSession.on_event(session, :response_generated, &handle_response_generated/2)
    AgentSession.on_event(session, :speaking_started, &handle_speaking_started/1)

    # Conversation turn events
    AgentSession.on_event(session, :turn_started, &handle_turn_started/1)
    AgentSession.on_event(session, :turn_completed, &handle_turn_completed/1)
  end

  # Event handlers

  def handle_session_started(session) do
    Logger.info("Session started: #{session.session_id}")

    # Send a greeting when session starts
    greeting = "Hello! I'm your voice assistant. How can I help you today?"
    AgentSession.generate_response(session, greeting)
  end

  def handle_session_stopped(session) do
    Logger.info("Session stopped: #{session.session_id}")
  end

  def handle_stt_result(session, %{transcript: transcript}) do
    Logger.info("User speech transcribed: #{transcript}")
  end

  def handle_text_received(session, %{text: text}) do
    Logger.info("Text received: #{text}")

    # Process the input and generate a response
    AgentSession.process_user_input(session, text)
  end

  def handle_response_generated(session, %{response: response}) do
    Logger.info("Assistant response: #{response}")
  end

  def handle_speaking_started(session) do
    Logger.info("Assistant started speaking in session: #{session.session_id}")
  end

  def handle_turn_started(session) do
    Logger.debug("Conversation turn started")
  end

  def handle_turn_completed(session) do
    Logger.debug("Conversation turn completed")
  end
end

# Configuration validation
defmodule ConfigValidator do
  def validate! do
    required_vars = [
      "OPENAI_API_KEY",
      "LIVEKIT_URL",
      "LIVEKIT_API_KEY",
      "LIVEKIT_API_SECRET"
    ]

    missing_vars =
      required_vars
      |> Enum.filter(&is_nil(System.get_env(&1)))

    unless Enum.empty?(missing_vars) do
      IO.puts("Error: Missing required environment variables:")
      Enum.each(missing_vars, &IO.puts("  #{&1}"))
      IO.puts("\nSet these environment variables and try again.")
      System.halt(1)
    end

    IO.puts("✓ All required environment variables are set")
  end
end

# Validate configuration and run
ConfigValidator.validate!()
MinimalRealtimeAssistant.run()
