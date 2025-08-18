# LivekitexAgent

An Elixir library that replicates LiveKit Agents functionality for voice agents. It provides building blocks for real‑time conversational AI: agents and sessions, function tools, workers, job/run contexts, and a Realtime WebSocket client for low‑latency audio conversations.

## Features

- Agent config: instructions, tools, components (LLM/STT/TTS/VAD placeholders)
- Agent sessions: conversation state, turns, interruptions, event callbacks
- Function tools: register functions, validate args, generate OpenAI function schemas
- Job/Run contexts: participants, tasks, logging; execution context for tools
- Workers: options, balancing, manager/supervisor, health scaffolding
- CLI: dev/prod start, health checks, config file support
- Realtime WebSocket (audio): stream PCM16 audio, send text, receive streamed responses, basic audio playback on macOS

## Requirements

- Elixir ~> 1.12
- macOS for built‑in audio playback via `afplay` (optional)
- Optional: OpenAI API key for Realtime via WebSocket

## Installation

Add to `mix.exs`:

```elixir
def deps do
  [
    {:livekitex_agent, "~> 0.1.0"}
  ]
end
```

Install deps:

```bash
mix deps.get
```

## Quick start

### 1) Create an agent

```elixir
agent = LivekitexAgent.Agent.new(
  instructions: "You are a helpful voice assistant. Be concise and friendly.",
  tools: [:get_weather, :add_numbers],
  agent_id: "my_voice_agent"
)
```

### 2) Start a session and send text

```elixir
{:ok, session} = LivekitexAgent.AgentSession.start_link(
  agent: agent,
  event_callbacks: %{
    session_started: fn _evt, data -> IO.inspect(data, label: "session_started") end,
    text_received: fn _evt, data -> IO.inspect(data, label: "text_received") end
  }
)

LivekitexAgent.AgentSession.process_text(session, "What's the weather like in Madrid?")
```

### 3) Register and use function tools

Option A: Register explicit tool definitions (see `LivekitexAgent.ExampleTools`):

```elixir
tools = LivekitexAgent.ExampleTools.get_tools()
Enum.each(tools, fn {_name, defn} -> LivekitexAgent.ToolRegistry.register(defn) end)

# Execute a tool
{:ok, result} = LivekitexAgent.FunctionTool.execute_tool("get_weather", %{"location" => "Madrid"})
```

Option B: Macro‑based tools with `use LivekitexAgent.FunctionTool` and `@tool`:

```elixir
defmodule MyTools do
  use LivekitexAgent.FunctionTool

  @tool "Get weather information for a location"
  @spec get_weather(String.t()) :: String.t()
  def get_weather(location), do: "Weather in #{location}: Sunny, 25°C"

  @tool "Search with context"
  @spec search_web(String.t(), LivekitexAgent.RunContext.t()) :: String.t()
  def search_web(query, context) do
    LivekitexAgent.RunContext.log_info(context, "Searching: #{query}")
    "Search results for #{query}"
  end
end

LivekitexAgent.FunctionTool.register_module(MyTools)
```

Convert tools to OpenAI function schema:

```elixir
openai_tools = LivekitexAgent.FunctionTool.get_all_tools() |> Map.values() |> LivekitexAgent.FunctionTool.to_openai_format()
```

## Realtime conversation via WebSocket (audio + text)

El módulo `LivekitexAgent.RealtimeWSClient` implementa un cliente WS para Realtime y está integrado en `AgentSession`.

Variables de entorno recomendadas:

- `OPENAI_API_KEY` o `OAI_API_KEY`
- `OAI_REALTIME_URL` (opcional). Por defecto: `wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17`

Inicio rápido:

```elixir
# Arranca una sesión con WS Realtime
pid = LivekitexAgent.Example.start_realtime_example()

# Envía texto y pide respuesta
LivekitexAgent.AgentSession.send_text(pid, "Hola, ¿quién eres?")

# Envía audio PCM16 (mono, 16kHz) y cierra turno
LivekitexAgent.AgentSession.stream_audio(pid, pcm16_chunk)
LivekitexAgent.AgentSession.commit_audio(pid)

# Cancelar respuesta en curso
LivekitexAgent.AgentSession.cancel_response(pid)
```

Configuración manual de Realtime al iniciar la sesión:

```elixir
rt_cfg = %{
  url: System.get_env("OAI_REALTIME_URL"),
  api_key: System.get_env("OPENAI_API_KEY"),
  # opcionales: log_frames: true, client_event_names: %{...}
}

{:ok, session} = LivekitexAgent.AgentSession.start_link(agent: agent, realtime_config: rt_cfg)
```

El cliente soporta por defecto eventos tipo:

- Cliente → servidor: `input_audio_buffer.append`, `input_audio_buffer.commit`, `input_text.append`, `response.create`, `response.cancel`.
- Servidor → cliente: eventos `response.*` y deltas con campos de audio base64 comunes (`audio`, `delta`). Se decodifica a binario antes de reenviar a `AgentSession`.

Audio en macOS: `LivekitexAgent.AudioSink` reproduce PCM16 bufferizado usando `afplay` al completar la respuesta.

## Workers y jobs

Configurar un worker y supervisor:

```elixir
entry_point = fn job ->
  agent = LivekitexAgent.Agent.new(instructions: "You are helpful.")
  {:ok, session} = LivekitexAgent.AgentSession.start_link(agent: agent)
  Process.monitor(session)
  receive do
    {:DOWN, _ref, :process, ^session, _reason} -> :ok
  end
end

opts = LivekitexAgent.WorkerOptions.new(
  entry_point: entry_point,
  agent_name: "my_agent",
  server_url: "wss://your-livekit-server",
  api_key: "your-api-key",
  max_concurrent_jobs: 5
)

{:ok, _sup} = LivekitexAgent.WorkerSupervisor.start_link(opts)
```

Asignar un job (mock):

```elixir
{:ok, job_id} = LivekitexAgent.WorkerManager.assign_job(%{room: %{name: "room1"}})
```

## JobContext y RunContext

JobContext:

```elixir
{:ok, job} = LivekitexAgent.JobContext.start_link(job_id: "job_123")
LivekitexAgent.JobContext.add_participant(job, "user_1", %{name: "Alice"})
LivekitexAgent.JobContext.start_task(job, "bg", fn -> :timer.sleep(1000) end)
info = LivekitexAgent.JobContext.get_info(job)
LivekitexAgent.JobContext.shutdown(job)
```

RunContext dentro de una tool:

```elixir
ctx = LivekitexAgent.RunContext.new(session: nil, function_call: %{name: "get_weather", arguments: %{"location" => "Madrid"}})
LivekitexAgent.RunContext.log_info(ctx, "Running tool")
```

## CLI

```bash
# Desarrollo
mix run -e "LivekitexAgent.CLI.main(['dev', '--hot-reload', '--log-level', 'debug'])"

# Producción
mix run -e "LivekitexAgent.CLI.main(['start', '--agent-name', 'prod_agent', '--production', '--server-url', 'wss://your-livekit'])"

# Salud
mix run -e "LivekitexAgent.CLI.main(['health'])"
```

Config por archivo (JSON):

```json
{
  "agent_name": "production_agent",
  "server_url": "wss://prod.livekit.cloud",
  "api_key": "your-production-key",
  "api_secret": "your-production-secret",
  "max_jobs": 10,
  "log_level": "info",
  "timeout": 300000
}
```

```bash
mix run -e "LivekitexAgent.CLI.main(['start', '--config-file', './config/production.json'])"
```

## Desarrollo y pruebas

```bash
mix deps.get
mix compile
mix test
mix test --cover
```

Calidad de código (opcional):

```bash
mix credo
mix dialyzer
mix docs
```

## Arquitectura

```
LivekitexAgent.Application
├── LivekitexAgent.ToolRegistry (registro global de tools)
└── LivekitexAgent.WorkerSupervisor (por worker)
    ├── LivekitexAgent.WorkerManager (distribución de jobs)
    └── LivekitexAgent.HealthServer (scaffolding de health)
```

Cada sesión de agente es un GenServer. Los jobs se ejecutan en procesos aislados y se monitorean.

## Módulos principales

- `LivekitexAgent.Agent`: configuración del agente
- `LivekitexAgent.AgentSession`: ciclo de vida y eventos; integra Realtime WS opcional
- `LivekitexAgent.RealtimeWSClient`: cliente WebSocket orientado a OpenAI Realtime
- `LivekitexAgent.AudioSink`: reproducción simple de PCM16 (macOS)
- `LivekitexAgent.FunctionTool`: macros/utilidades para tools
- `LivekitexAgent.ToolRegistry`: registro global de tools
- `LivekitexAgent.RunContext` y `LivekitexAgent.JobContext`: contextos de ejecución
- `LivekitexAgent.WorkerOptions`, `WorkerManager`, `WorkerSupervisor`, `HealthServer`

## Consejos y solución de problemas

- Realtime WS requiere API key si el servidor la exige. Exporta `OPENAI_API_KEY`.
- Audio: envía PCM16 mono 16kHz. Si usas otra frecuencia, convierte o ajusta sinks.
- macOS: `afplay` debe estar disponible para reproducción.
- Los nombres de eventos Realtime se pueden ajustar en `realtime_config.client_event_names`.

## Licencia

MIT. Ver `LICENSE`.
