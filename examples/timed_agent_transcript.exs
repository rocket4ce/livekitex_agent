#!/usr/bin/env elixir
Mix.install([
  {:jason, "~> 1.4"}
])

Code.append_path("lib")
Code.compile_file("lib/livekitex_agent.ex")
Code.compile_file("lib/livekitex_agent/agent.ex")
Code.compile_file("lib/livekitex_agent/agent_session.ex")
Code.compile_file("lib/livekitex_agent/audio_sink.ex")

# This example simulates TTS-aligned transcript by emitting TimedString-like logs.
# We don't have a built-in TTS with word timings, so we simulate it.

agent = LivekitexAgent.Agent.new(instructions: "You are a helpful assistant.")
{:ok, session} = LivekitexAgent.AgentSession.start_link(agent: agent)

# Simulate a response broken into timed chunks
chunks = [
  {"Hello", 0.0, 0.5},
  {", ", 0.5, 0.6},
  {"world", 0.6, 1.1},
  {"!", 1.1, 1.2}
]

parent = self()
spawn_link(fn ->
  Enum.each(chunks, fn {text, s, e} ->
    send(parent, {:realtime_event, %{"type" => "response.output_text.delta", "text" => text, "start_time" => s, "end_time" => e}})
    Process.sleep(150)
  end)
  send(parent, {:realtime_event, %{"type" => "response.completed"}})
end)

# Minimal event logger
LivekitexAgent.AgentSession.register_callback(session, :response_delta, fn _evt, data ->
  if Map.has_key?(data, "text") do
    IO.puts("TimedString: '#{data["text"]}' (#{data["start_time"]} - #{data["end_time"]})")
  end
end)

Process.sleep(2_000)
