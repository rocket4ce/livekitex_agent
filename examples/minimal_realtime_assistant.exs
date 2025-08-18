#!/usr/bin/env elixir
# Minimal realtime voice assistant in Spanish using OpenAI Realtime via LivekitexAgent.RealtimeWSClient
# Run with: mix run examples/minimal_realtime_assistant.exs
# Environment:
#   OPENAI_API_KEY or OAI_API_KEY
#   OAI_REALTIME_URL (optional)

api_key = System.get_env("OPENAI_API_KEY") || System.get_env("OAI_API_KEY") || ""
url = System.get_env("OAI_REALTIME_URL") ||
        "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17"

if api_key == "" do
  IO.puts("OPENAI_API_KEY is required in your environment.")
  System.halt(1)
end

agent = LivekitexAgent.Agent.new(
  instructions: "Eres un asistente de voz útil. Habla español.",
  tools: [],
  agent_id: "inbound_agent"
)

rt_cfg = %{
  url: url,
  # fuerza el header explícitamente
  auth_header: {"Authorization", "Bearer " <> api_key},
  beta_header: {"OpenAI-Beta", "realtime=v1"},
  protocol_header: {"Sec-WebSocket-Protocol", "realtime"},
  log_frames: true
}

callbacks = %{
  response_delta: fn _evt, data ->
    # Print transcript deltas only; ignore raw audio binary deltas
    cond do
      is_binary(Map.get(data, "text")) -> IO.write(Map.get(data, "text"))
      is_binary(Map.get(data, "delta")) and String.printable?(Map.get(data, "delta")) ->
        IO.write(Map.get(data, "delta"))
      true -> :ok
    end
  end,
  response_completed: fn _evt, _data -> IO.puts("") end
}

{:ok, session} = LivekitexAgent.AgentSession.start_link(agent: agent, realtime_config: rt_cfg, event_callbacks: callbacks)

# Ask the model to greet the user as requested (similar to generate_reply in Python)
LivekitexAgent.AgentSession.send_text(session, "Greet the user and offer your assistance. Preséntate como Dinko ASS y saluda cordialmente, en español.")

# Keep the script alive briefly to receive output (adjust as needed)
Process.sleep(5_000)
