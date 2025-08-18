defmodule LivekitexAgentTest do
  use ExUnit.Case
  doctest LivekitexAgent

  test "creates an agent with default options" do
    agent = LivekitexAgent.create_agent()
    assert %LivekitexAgent.Agent{} = agent
    assert agent.instructions == ""
    assert agent.tools == []
    assert is_binary(agent.agent_id)
  end

  test "creates an agent with custom options" do
    agent =
      LivekitexAgent.create_agent(
        instructions: "You are a test assistant",
        tools: [:test_tool]
      )

    assert agent.instructions == "You are a test assistant"
    assert agent.tools == [:test_tool]
  end

  test "creates job context" do
    job_context =
      LivekitexAgent.create_job_context(
        job_id: "test_job",
        metadata: %{test: true}
      )

    assert job_context.job_id == "test_job"
    assert job_context.metadata[:test] == true
    assert job_context.status == :created
  end

  test "creates worker options" do
    entry_point = fn _job -> :ok end

    worker_options =
      LivekitexAgent.worker_options(
        entry_point: entry_point,
        agent_name: "test_agent"
      )

    assert worker_options.entry_point == entry_point
    assert worker_options.agent_name == "test_agent"
  end
end
