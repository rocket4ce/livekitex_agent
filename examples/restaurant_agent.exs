#!/usr/bin/env elixir
Mix.install([
  {:jason, "~> 1.4"}
])

Code.append_path("lib")
Code.compile_file("lib/livekitex_agent.ex")
Code.compile_file("lib/livekitex_agent/agent.ex")
Code.compile_file("lib/livekitex_agent/agent_session.ex")
Code.compile_file("lib/livekitex_agent/function_tool.ex")
Code.compile_file("lib/livekitex_agent/tool_registry.ex")

# Multi-agent handoff simulation similar to Python restaurant example.

voices = %{
  greeter: "voice_greeter",
  reservation: "voice_reservation",
  takeaway: "voice_takeaway",
  checkout: "voice_checkout"
}

# Shared user data
userdata = %{
  customer_name: nil,
  customer_phone: nil,
  reservation_time: nil,
  order: nil,
  customer_credit_card: nil,
  customer_credit_card_expiry: nil,
  customer_credit_card_cvv: nil,
  expense: nil,
  checked_out: false
}

# Tools manipulating userdata
parent = self()
:ets.new(:userdata, [:named_table, :public, {:read_concurrency, true}])
:ets.insert(:userdata, {:data, userdata})

get_ud = fn -> [{:data, m}] = :ets.lookup(:userdata, :data); m end
put_ud = fn m -> :ets.insert(:userdata, {:data, Map.merge(get_ud.(), m)}) end

# Tool functions

defmodule Examples.RestaurantTools do
  def update_name(%{"name" => name}) do
    send(Process.get(:parent), {:ud_merge, %{customer_name: name}})
    "The name is updated to #{name}"
  end

  def update_phone(%{"phone" => phone}) do
    send(Process.get(:parent), {:ud_merge, %{customer_phone: phone}})
    "The phone number is updated to #{phone}"
  end
end

Process.put(:parent, parent)

{:ok, _} = LivekitexAgent.ToolRegistry.start_link([])
LivekitexAgent.FunctionTool.register_tool(%{name: "update_name", description: "Update customer name", module: Examples.RestaurantTools, function: :update_name, arity: 1, parameters: [%{name: "name", type: "string", required: true, position: 0}]})
LivekitexAgent.FunctionTool.register_tool(%{name: "update_phone", description: "Update customer phone", module: Examples.RestaurantTools, function: :update_phone, arity: 1, parameters: [%{name: "phone", type: "string", required: true, position: 0}]})

# Greeter agent -> can transfer via a simulated tool call sequence
agent = LivekitexAgent.Agent.new(
  instructions: "You are a friendly restaurant receptionist. Guide the user to reservation or takeaway.",
  tools: [:update_name, :update_phone]
)

parent = self()
llm = spawn_link(fn ->
  receive do
    {:process_message, text, _ctx, _inst} ->
      lower = String.downcase(text)
      cond do
        String.contains?(lower, "name is") ->
          name = String.split(text) |> List.last()
          send(parent, {:llm_response, %{tool_calls: [%{"name" => "update_name", "arguments" => %{"name" => name}}]}})
        String.contains?(lower, "phone") ->
          send(parent, {:llm_response, %{tool_calls: [%{"name" => "update_phone", "arguments" => %{"phone" => "+34 600 000 000"}}]}})
        true ->
          send(parent, {:llm_response, "Would you like to make a reservation or order takeaway?"})
      end
  end
  receive do
    {:continue_with_context, _ctx} ->
      send(parent, {:llm_response, "Thanks, noted."})
  end
end)

{:ok, session} = LivekitexAgent.AgentSession.start_link(agent: agent, llm_client: llm)

# Merge updates from tools
spawn_link(fn ->
  receive do
    {:ud_merge, delta} -> put_ud.(delta)
  end
end)

IO.puts("Say: my name is Alice")
LivekitexAgent.AgentSession.process_text(session, "my name is Alice")
Process.sleep(1000)

IO.puts("Say: my phone number is ...")
LivekitexAgent.AgentSession.process_text(session, "my phone number is +34 600 000 000")
Process.sleep(1000)

IO.inspect(get_ud.(), label: "UserData")
