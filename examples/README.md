# Examples

This folder contains runnable Elixir examples that mirror the Python voice-agent examples:

- push_to_talk.exs
- weather_agent.exs
- timed_agent_transcript.exs
- realtime_joke_teller.exs
- restaurant_agent.exs

Notes

- These examples use the library modules in `lib/` and avoid external LiveKit room bindings.
- Realtime audio/text uses `LivekitexAgent.RealtimeWSClient` (OpenAI Realtime compatible).
- Tool calls are demonstrated via a small Dummy LLM that emits tool_call messages; this is for local demonstration only.

Environment

- OPENAI_API_KEY or OAI_API_KEY: API key for OpenAI Realtime (optional for Realtime examples; required to actually get responses)
- OAI_REALTIME_URL: WebSocket URL, default: wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17

Run

Use Mix to run each script:

```
mix run examples/push_to_talk.exs
mix run examples/weather_agent.exs
mix run examples/timed_agent_transcript.exs
mix run examples/realtime_joke_teller.exs
mix run examples/restaurant_agent.exs
```

Audio input

- For push-to-talk, you can stream a mono 16 kHz PCM16 WAV file using `start <path.wav>` then `commit`.
- Audio playback is supported on macOS via `LivekitexAgent.AudioSink` when the server sends audio frames.

Limitations vs Python

- No LiveKit Room/RPC in these examples; push-to-talk is simulated via terminal commands.
- Tool calls aren’t triggered by Realtime server; instead we simulate them with `DummyLLM` in the non-realtime examples.
