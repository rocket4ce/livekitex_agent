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

# Simple realtime-like joke teller using a dummy tool and mock LLM

defmodule Examples.JokeTools do
  def get_weather(%{"city" => city, "units" => units}) do
    temp = Enum.random(20..35)
    %{"temperature" => temp, "units" => units, "city" => city}
  end

  def get_median_home_price(%{"location" => loc}) do
    price = Enum.random(100_000..1_000_000)
    %{"median_home_price" => "$#{:erlang.integer_to_list(price)}", "location" => loc}
  end

  def search_web(%{"query" => q, "max_results" => _max}) do
    %{"0" => %{"title" => "Result about #{q}", "url" => "https://example.com", "body" => "Snippet"}}
  end

  def tell_joke(%{"category" => cat}) do
    %{"joke" => "A #{Enum.join(cat, ", ")} joke walks into a bar..."}
  end

  def defs do
    [
      %{name: "get_weather", description: "Retrieve weather", module: __MODULE__, function: :get_weather, arity: 1, parameters: [%{name: "city", type: "string", required: true, position: 0}, %{name: "units", type: "string", required: false, position: 1}]},
      %{name: "get_median_home_price", description: "Median home price", module: __MODULE__, function: :get_median_home_price, arity: 1, parameters: [%{name: "location", type: "string", required: true, position: 0}]},
      %{name: "search_web", description: "Search web", module: __MODULE__, function: :search_web, arity: 2, parameters: [%{name: "query", type: "string", required: true, position: 0}, %{name: "max_results", type: "integer", required: false, position: 1}]},
      %{name: "tell_joke", description: "Tell a joke", module: __MODULE__, function: :tell_joke, arity: 1, parameters: [%{name: "category", type: "array", required: false, position: 0}]}
    ]
  end
end

{:ok, _} = LivekitexAgent.ToolRegistry.start_link([])
Examples.JokeTools.defs() |> Enum.each(&LivekitexAgent.FunctionTool.register_tool/1)

agent = LivekitexAgent.Agent.new(
  instructions: "You are a helpful voice AI assistant.",
  tools: [:get_weather, :get_median_home_price, :search_web, :tell_joke]
)

parent = self()
llm = spawn_link(fn ->
  receive do
    {:process_message, _txt, _ctx, _inst} ->
      # Ask model to call a tool first
      send(parent, {:llm_response, %{tool_calls: [%{"name" => "tell_joke", "arguments" => %{"category" => ["Programming"]}}]}})
  end
  receive do
    {:continue_with_context, _ctx} ->
      send(parent, {:llm_response, "Here is your joke!"})
  end
end)

{:ok, session} = LivekitexAgent.AgentSession.start_link(agent: agent, llm_client: llm)
LivekitexAgent.AgentSession.process_text(session, "Tell me a programming joke")
Process.sleep(2_000)
