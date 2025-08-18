defmodule LivekitexAgent do
  @moduledoc """
  LivekitexAgent - An Elixir library that replicates LiveKit Agents functionality.

  This library provides voice agent capabilities including:
  - Agent configuration and behavior
  - Session management for voice interactions
  - Job context and execution
  - Worker management and options
  - Function tools for LLM integration
  - CLI utilities for running agents
  """

  alias LivekitexAgent.{Agent, AgentSession, JobContext, WorkerOptions}

  @doc """
  Creates a new agent with the given configuration.
  """
  def create_agent(opts \\ []) do
    Agent.new(opts)
  end

  @doc """
  Starts a new agent session.
  """
  def start_session(agent, opts \\ []) do
    AgentSession.start_link(Keyword.put(opts, :agent, agent))
  end

  @doc """
  Creates a job context for agent execution.
  """
  def create_job_context(opts \\ []) do
    JobContext.new(opts)
  end

  @doc """
  Configures worker options.
  """
  def worker_options(opts \\ []) do
    WorkerOptions.new(opts)
  end
end
