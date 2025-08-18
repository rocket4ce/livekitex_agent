#!/usr/bin/env elixir
Mix.install([
  {:jason, "~> 1.4"},
  {:httpoison, "~> 2.2"}
])

Code.append_path("lib")
Code.compile_file("lib/livekitex_agent.ex")
Code.compile_file("lib/livekitex_agent/agent.ex")
Code.compile_file("lib/livekitex_agent/agent_session.ex")
Code.compile_file("lib/livekitex_agent/function_tool.ex")
Code.compile_file("lib/livekitex_agent/tool_registry.ex")

# Weather tool using open-meteo.com similar to python example

defmodule Examples.WeatherTools do
  @moduledoc false

  @spec get_weather(String.t(), String.t()) :: map()
  def get_weather(latitude, longitude) do
    url = "https://api.open-meteo.com/v1/forecast?latitude=#{latitude}&longitude=#{longitude}&current=temperature_2m"
    case HTTPoison.get(url, [], recv_timeout: 5_000, timeout: 5_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"current" => %{"temperature_2m" => temp}}} ->
            %{"temperature" => temp, "temperature_unit" => "Celsius"}

          _ -> %{"error" => "unexpected_response"}
        end

      {:ok, %HTTPoison.Response{status_code: code}} ->
        %{"error" => "http_#{code}"}

      {:error, err} -> %{"error" => inspect(err)}
    end
  end

  def tool_definitions do
    [
      %{
        name: "get_weather",
        description: "Return weather for the given latitude and longitude",
        module: __MODULE__,
        function: :get_weather,
        arity: 2,
        parameters: [
          %{name: "latitude", type: "string", required: true, position: 0},
          %{name: "longitude", type: "string", required: true, position: 1}
        ]
      }
    ]
  end
end

{:ok, _} = LivekitexAgent.ToolRegistry.start_link([])
Examples.WeatherTools.tool_definitions() |> Enum.each(&LivekitexAgent.FunctionTool.register_tool/1)

agent = LivekitexAgent.Agent.new(
  instructions: "You are a weather agent.",
  tools: [:get_weather]
)

# Dummy LLM: demonstrates triggering a tool call based on a prompt
parent = self()
llm = spawn_link(fn ->
  receive do
    {:process_message, text, _ctx, _inst} ->
      if String.contains?(String.downcase(text), "weather") do
        call = %{tool_calls: [%{"name" => "get_weather", "arguments" => %{"latitude" => "40.7", "longitude" => "-74.0"}}]}
        send(parent, {:llm_response, call})
      else
        send(parent, {:llm_response, "I can tell you the weather if you provide a location."})
      end
  end
end)

{:ok, session} = LivekitexAgent.AgentSession.start_link(agent: agent, llm_client: llm)

LivekitexAgent.AgentSession.process_text(session, "What's the weather like in New York?")
Process.sleep(2_000)
