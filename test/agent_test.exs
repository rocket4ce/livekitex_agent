defmodule LivekitexAgent.AgentTest do
  use ExUnit.Case

  describe "Agent" do
    test "creates an agent with default values" do
      agent = LivekitexAgent.Agent.new()

      assert agent.instructions == ""
      assert agent.tools == []
      assert agent.chat_context == %{}
      assert is_binary(agent.agent_id)
    end

    test "creates an agent with custom configuration" do
      agent =
        LivekitexAgent.Agent.new(
          instructions: "You are helpful",
          tools: [:weather, :math],
          agent_id: "custom_agent"
        )

      assert agent.instructions == "You are helpful"
      assert agent.tools == [:weather, :math]
      assert agent.agent_id == "custom_agent"
    end

    test "updates agent instructions" do
      agent = LivekitexAgent.Agent.new()
      updated = LivekitexAgent.Agent.update_instructions(agent, "New instructions")

      assert updated.instructions == "New instructions"
      # Original unchanged
      assert agent.instructions == ""
    end

    test "adds tools to agent" do
      agent = LivekitexAgent.Agent.new()
      updated = LivekitexAgent.Agent.add_tool(agent, :new_tool)

      assert :new_tool in updated.tools
      # Original unchanged
      assert agent.tools == []
    end
  end
end
