#!/usr/bin/env elixir
Mix.install([
  {:jason, "~> 1.4"}
])

# Minimal realtime voice assistant in Spanish using OpenAI Realtime via LivekitexAgent.RealtimeWSClient
# Environment:
#   OPENAI_API_KEY or OAI_API_KEY
#   OAI_REALTIME_URL (optional)

Code.append_path("lib")
Code.compile_file("lib/livekitex_agent.ex")
Code.compile_file("lib/livekitex_agent/agent.ex")
Code.compile_file("lib/livekitex_agent/agent_session.ex")
Code.compile_file("lib/livekitex_agent/realtime_ws_client.ex")
Code.compile_file("lib/livekitex_agent/audio_sink.ex")

api_key = System.get_env("OPENAI_API_KEY") || System.get_env("OAI_API_KEY")
url = System.get_env("OAI_REALTIME_URL") ||
        "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17"

agent = LivekitexAgent.Agent.new(
  instructions: "Eres un asistente de voz útil. Habla español.",
  tools: [],
  agent_id: "inbound_agent"
)

rt_cfg = %{
  url: url,
  api_key: api_key,
  log_frames: true
}

callbacks = %{
  response_delta: fn _evt, data ->
    text = Map.get(data, "text") || Map.get(data, "delta")
    if is_binary(text), do: IO.write(text)
  end,
  response_completed: fn _evt, _data -> IO.puts("") end
}

{:ok, session} = LivekitexAgent.AgentSession.start_link(agent: agent, realtime_config: rt_cfg, event_callbacks: callbacks)

# Ask the model to greet the user as requested (similar to generate_reply in Python)
LivekitexAgent.AgentSession.send_text(session, "Greet the user and offer your assistance. Preséntate como Dinko ASS y saluda cordialmente, en español.")

# Keep the script alive briefly to receive output (adjust as needed)
Process.sleep(5_000)
