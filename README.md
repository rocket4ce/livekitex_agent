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

## Integración con Phoenix: ejemplo de la vida real

Esta sección muestra cómo usar la librería dentro de una app Phoenix para un flujo de “cliente que llama”. No requiere LiveKit Room aún; usamos un endpoint HTTP/WS propio para recibir audio/órdenes y orquestar un `AgentSession` por llamada.

### Flujo del cliente que llama

1) Persona llama por teléfono
2) Le responde un agente de forma amable y pregunta cómo ayudar
3) El usuario hace preguntas; la IA consulta datos de productos y precios (tools)
4) El usuario empieza a pedir (toma de pedido)
5) El agente da un resumen
6) Pide teléfono y dirección para delivery
7) Fin de la conversación

### Arquitectura sugerida

- Un `Registry` para mapear `call_id -> pid` de `AgentSession`.
- Un conjunto de endpoints Phoenix (HTTP o WebSocket) que permitan:
  - crear/cerrar sesión por llamada
  - enviar audio PCM16 (stream) y confirmar turno
  - enviar texto (DTMF, IVR o chat web)
  - cancelar respuesta
- Tools que acceden a catálogo y precios internos.

### Tools de ejemplo (catálogo y pedidos)

```elixir
defmodule MyApp.Tools.Catalog do
  @moduledoc """
  Tools para consultar productos y precios.
  """
  use LivekitexAgent.FunctionTool

  @catalog %{
    "pizza" => %{precio: 10.0, stock: 50},
    "ensalada" => %{precio: 5.0, stock: 100},
    "helado" => %{precio: 3.0, stock: 40}
  }

  @tool "Consultar precio y stock de un producto"
  @spec get_product_info(String.t(), LivekitexAgent.RunContext.t()) :: String.t()
  def get_product_info(nombre, ctx) do
    case Map.get(@catalog, String.downcase(nombre)) do
      nil -> "No encuentro el producto: #{nombre}"
      %{precio: p, stock: s} ->
        LivekitexAgent.RunContext.log_info(ctx, "Consulta producto #{nombre}")
        "#{nombre}: precio $#{p}, stock #{s}"
    end
  end
end
```

Registro global de tools (ej. en tu árbol de supervisión):

```elixir
children = [
  {LivekitexAgent.ToolRegistry, []}
]
Supervisor.start_link(children, strategy: :one_for_one)

# En arranque de tu app:
LivekitexAgent.FunctionTool.register_module(MyApp.Tools.Catalog)
```

### Sesión del agente por llamada

```elixir
defmodule MyApp.Voice.AgentSessions do
  @moduledoc false
  # Utilidad para crear/buscar sesiones por call_id

  def start_for_call(call_id, opts \\ []) do
    agent = LivekitexAgent.Agent.new(
      instructions: "Eres un agente de atención amable. Responde brevemente, usa tools para catálogo y precios. Al final resume el pedido y solicita teléfono y dirección para el delivery.",
      tools: [:get_product_info]
    )

    rt_cfg = opts[:realtime_config] # opcional (OpenAI Realtime WS)
    {:ok, pid} = LivekitexAgent.AgentSession.start_link(agent: agent, realtime_config: rt_cfg)
    Registry.register(MyApp.Registry.Calls, call_id, pid)
    {:ok, pid}
  end

  def whereis(call_id) do
    case Registry.lookup(MyApp.Registry.Calls, call_id) do
      [{pid, _}] -> {:ok, pid}
      _ -> :error
    end
  end
end
```

Registry en tu app (ej. `application.ex`):

```elixir
children = [
  {Registry, keys: :unique, name: MyApp.Registry.Calls},
  {LivekitexAgent.ToolRegistry, []}
]
```

### Endpoints Phoenix (HTTP) para orquestar la llamada

```elixir
defmodule MyAppWeb.CallController do
  use MyAppWeb, :controller

  def start(conn, %{"id" => call_id}) do
    {:ok, _pid} = MyApp.Voice.AgentSessions.start_for_call(call_id, realtime_config: realtime_cfg())
    json(conn, %{ok: true})
  end

  # Recibir audio PCM16 (mono 16kHz) chunk; body binario o Base64
  def audio(conn, %{"id" => call_id}) do
    with {:ok, pid} <- MyApp.Voice.AgentSessions.whereis(call_id) do
      pcm = conn.assigns[:raw_body] || conn.body_params["pcm_b64"] |> Base.decode64!()
      LivekitexAgent.AgentSession.stream_audio(pid, pcm)
      json(conn, %{ok: true})
    else
      _ -> send_resp(conn, 404, "no session")
    end
  end

  # Final de turno de usuario
  def commit(conn, %{"id" => call_id}) do
    with {:ok, pid} <- MyApp.Voice.AgentSessions.whereis(call_id) do
      LivekitexAgent.AgentSession.commit_audio(pid)
      json(conn, %{ok: true})
    else
      _ -> send_resp(conn, 404, "no session")
    end
  end

  # Texto opcional (IVR/DTMF convertido a texto, chat web, etc.)
  def text(conn, %{"id" => call_id, "q" => q}) do
    with {:ok, pid} <- MyApp.Voice.AgentSessions.whereis(call_id) do
      LivekitexAgent.AgentSession.send_text(pid, q)
      json(conn, %{ok: true})
    else
      _ -> send_resp(conn, 404, "no session")
    end
  end

  def cancel(conn, %{"id" => call_id}) do
    with {:ok, pid} <- MyApp.Voice.AgentSessions.whereis(call_id) do
      LivekitexAgent.AgentSession.cancel_response(pid)
      json(conn, %{ok: true})
    else
      _ -> send_resp(conn, 404, "no session")
    end
  end

  defp realtime_cfg do
    %{
      url: System.get_env("OAI_REALTIME_URL") || "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17",
      api_key: System.get_env("OPENAI_API_KEY") || System.get_env("OAI_API_KEY")
    }
  end
end
```

Router ejemplo:

```elixir
scope "/api", MyAppWeb do
  pipe_through [:api]
  post "/calls/:id/start", CallController, :start
  post "/calls/:id/audio", CallController, :audio
  post "/calls/:id/commit", CallController, :commit
  post "/calls/:id/text", CallController, :text
  post "/calls/:id/cancel", CallController, :cancel
end
```

### Cómo se mapea al flujo

- Al entrar la llamada (1), tu PBX/telephony gateway invoca `POST /api/calls/:id/start` para crear la sesión.
- El agente saluda (2). Puedes disparar un primer `send_text/2` con instrucciones de saludo.
- El usuario pregunta (3): envías audio chunks a `/audio` y luego `/commit`; el agente, con ayuda de tools (catálogo), responde.
- El usuario pide (4): sigue el mismo ciclo; las tools pueden acumular items y cantidades en `RunContext`/`user_data`.
- Resumen (5): el agente hace un resumen; puedes tener una tool `summarize_order/1`.
- Teléfono y dirección (6): tools para `update_phone`, `update_address` que validan datos.
- Fin (7): cierra la sesión y persiste el pedido.

Consejos

- Asegura PCM16 mono 16kHz para audio. Si recibes otra frecuencia, convierte antes de `stream_audio/2`.
- Usa `event_callbacks` de `AgentSession` para loggear, métricas o publicar a websockets front.
- Persiste el estado del pedido en DB desde las tools (mediante tu contexto de negocio) usando el `RunContext`.
