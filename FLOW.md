# LiveKit Agents Worker - Flujo Completo

## Introducción

Este documento detalla el funcionamiento completo del Worker de LiveKit Agents, desde el comando inicial hasta el manejo de conversaciones telefónicas. El Worker actúa como un **dispatcher inteligente** que gestiona agentes de voz para llamadas entrantes.

## Arquitectura General

```
┌─────────────────────────────────────────────────────────────────┐
│                        Worker (Main Class)                      │
├─────────────────────────────────────────────────────────────────┤
│  • Maneja conexiones WebSocket con LiveKit Server              │
│  • Coordina ejecución de jobs                                  │
│  • Monitorea carga del sistema                                 │
│  • Expone servidor HTTP para health checks                     │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Componentes Principales                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────┐ │
│  │   ProcPool      │    │  HTTP Server    │    │LoadCalc     │ │
│  │ (Job Executor)  │    │ (Health Check)  │    │(CPU Monitor)│ │
│  └─────────────────┘    └─────────────────┘    └─────────────┘ │
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐                    │
│  │InferenceExecutor│    │  WebSocket      │                    │
│  │   (Optional)    │    │  Connection     │                    │
│  └─────────────────┘    └─────────────────┘                    │
└─────────────────────────────────────────────────────────────────┘
```

## Flujo Completo: De Comando a Conversación

### 1. **Inicio del Comando**
```bash
uv run python test.py start
```

### 2. **Inicialización del Worker**
````python
# En test.py se ejecuta algo como:
worker = Worker(WorkerOptions(
    entrypoint_fnc=my_voice_agent,
    request_fnc=should_accept_call,
))
await worker.run()
````

### 3. **Secuencia de Startup (Logs iniciales)**

#### Componentes que se inicializan:

```
┌─────────────────────────────────────────────────────────────────┐
│ {"message": "starting worker", "version": "1.2.5"}             │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│           Worker.run() - Inicialización                        │
├─────────────────────────────────────────────────────────────────┤
│  1. Configurar multiprocessing context                         │
│  2. Inicializar inference executor (si existe)                 │
│  3. Crear process pool con 4 procesos idle:                    │
│     • {"message": "initializing process", "pid": 66492}        │
│     • {"message": "initializing process", "pid": 66493}        │
│     • {"message": "initializing process", "pid": 66494}        │
│     • {"message": "initializing process", "pid": 66495}        │
│  4. Inicializar HTTP server (health check)                     │
│  5. Crear cliente HTTP session                                 │
│  6. Lanzar tareas asíncronas:                                  │
│     ├── _connection_task() - Conexión WebSocket                │
│     └── _load_task() - Monitor de carga                        │
└─────────────────────────────────────────────────────────────────┘
```

#### Código de inicialización:
````python
async def run(self) -> None:
    logger.info("starting worker", extra={"version": __version__})

    # 1. Configurar multiprocessing
    if self._opts.multiprocessing_context == "forkserver":
        plugin_packages = [p.package for p in Plugin.registered_plugins] + ["av"]
        self._mp_ctx.set_forkserver_preload(plugin_packages)

    # 2. Inicializar inference executor
    if self._inference_executor is not None:
        await self._inference_executor.start()
        await self._inference_executor.initialize()

    # 3. Inicializar servidores HTTP
    await self._http_server.start()
    if self._prometheus_server:
        await self._prometheus_server.start()

    # 4. Inicializar process pool
    await self._proc_pool.start()

    # 5. Crear cliente HTTP
    self._http_session = aiohttp.ClientSession(proxy=self._opts.http_proxy)
    self._api = api.LiveKitAPI(self._opts.ws_url, self._opts.api_key, self._opts.api_secret)

    # 6. Lanzar tareas asíncronas
    self._load_task = asyncio.create_task(_load_task())
    if self._register:
        self._conn_task = asyncio.create_task(self._connection_task())
````

### 4. **Conexión y Registro WebSocket**

#### Endpoint de registro:
- **URL Base**: Tomada de `ws_url` (ej: `wss://test-xzvcu3jl.livekit.cloud`)
- **Endpoint completo**: `wss://test-xzvcu3jl.livekit.cloud/agent`

#### Proceso de conexión:
````python
async def _connection_task(self):
    # 1. Crear JWT token para autenticación
    join_jwt = api.AccessToken(self._opts.api_key, self._opts.api_secret)
        .with_grants(api.VideoGrants(agent=True))
        .to_jwt()

    # 2. Construir URL del endpoint
    parse = urlparse(self._opts.ws_url)
    scheme = parse.scheme.replace("http", "ws")  # http -> ws, https -> wss
    base = f"{scheme}://{parse.netloc}{parse.path}".rstrip("/") + "/"
    agent_url = urljoin(base, "agent")  # .../agent

    # 3. Conectar WebSocket
    headers = {"Authorization": f"Bearer {join_jwt}"}
    params = {}
    if self._opts._worker_token:
        params["worker_token"] = self._opts._worker_token

    ws = await self._http_session.ws_connect(
        agent_url, headers=headers, params=params,
        autoping=True, heartbeat=HEARTBEAT_INTERVAL
    )

    # 4. Enviar mensaje de registro
    req = agent.WorkerMessage()
    req.register.type = self._opts.worker_type.value  # ROOM o PUBLISHER
    req.register.allowed_permissions.CopyFrom(
        models.ParticipantPermission(
            can_publish=self._opts.permissions.can_publish,
            can_subscribe=self._opts.permissions.can_subscribe,
            can_publish_data=self._opts.permissions.can_publish_data,
            can_update_metadata=self._opts.permissions.can_update_metadata,
            can_publish_sources=self._opts.permissions.can_publish_sources,
            hidden=self._opts.permissions.hidden,
            agent=True,
        )
    )
    req.register.agent_name = self._opts.agent_name
    req.register.version = __version__
    await ws.send_bytes(req.SerializeToString())

    # 5. Recibir respuesta de registro
    first_msg_b = await ws.receive_bytes()
    msg = agent.ServerMessage()
    msg.ParseFromString(first_msg_b)

    if not msg.HasField("register"):
        raise Exception("expected register response as first message")

    self._handle_register(msg.register)
````

#### Manejo de la respuesta de registro:
````python
def _handle_register(self, reg: agent.RegisterWorkerResponse) -> None:
    self._id = reg.worker_id  # Asignar ID único del worker
    logger.info(
        "registered worker",
        extra={
            "id": reg.worker_id,
            "url": self._opts.ws_url,
            "region": reg.server_info.region,
            "protocol": reg.server_info.protocol,
        },
    )
    self.emit("worker_registered", reg.worker_id, reg.server_info)
````

### 5. **Estado "Listening" - Worker Registrado**

Una vez registrado, el Worker mantiene tres tareas asíncronas principales:

```
┌─────────────────────────────────────────────────────────────────┐
│                 Worker Registrado y Escuchando                 │
├─────────────────────────────────────────────────────────────────┤
│  • WebSocket conectado a LiveKit Cloud                         │
│  • 4 procesos idle esperando jobs                              │
│  • Monitoreando carga CPU cada 0.5s                            │
│  • Enviando status cada 2.5s                                   │
│  • HTTP server corriendo en puerto 8081 (health check)         │
│                                                                 │
│  Estado: AVAILABLE para recibir llamadas                       │
└─────────────────────────────────────────────────────────────────┘
```

#### Tareas activas:

1. **_load_task()**: Monitorea carga del sistema cada 0.5s
````python
async def _load_task() -> None:
    interval = utils.aio.interval(UPDATE_LOAD_INTERVAL)  # 0.5s
    while True:
        await interval.tick()

        # Calcular carga actual
        self._worker_load = await asyncio.get_event_loop().run_in_executor(
            None, self._opts.load_fnc
        )

        # Ajustar número de procesos idle basado en carga
        load_threshold = _WorkerEnvOption.getvalue(self._opts.load_threshold, self._devmode)
        if not math.isinf(load_threshold):
            # Lógica para ajustar procesos disponibles
            self._proc_pool.set_target_idle_processes(available_job)
````

2. **_send_task()**: Envía mensajes al servidor
````python
async def _send_task() -> None:
    while True:
        msg = await self._msg_chan.recv()  # Espera mensajes en cola
        await ws.send_bytes(msg.SerializeToString())
````

3. **_recv_task()**: Recibe mensajes del servidor
````python
async def _recv_task() -> None:
    while True:
        msg = await ws.receive()
        server_msg = agent.ServerMessage()
        server_msg.ParseFromString(msg.data)

        which = server_msg.WhichOneof("message")
        if which == "availability":
            self._handle_availability(server_msg.availability)
        elif which == "assignment":
            self._handle_assignment(server_msg.assignment)
        elif which == "termination":
            await self._handle_termination(server_msg.termination)
````

## Creación de Salas

### ¿Quién crea las salas?

**El Worker NO crea salas**. Las salas son creadas por otros componentes:

#### 1. **SIP Gateway** (Para llamadas telefónicas)
```
┌─────────────────┐   1. Llamada SIP   ┌─────────────────┐
│   Teléfono      │ ─────────────────► │  SIP Gateway    │
│ +56975231235    │                    │   (LiveKit)     │
└─────────────────┘                    └─────────────────┘
                                               │
                                    2. Crea sala automáticamente
                                       "call-_+56975231235_kwJutxuFvEyA"
                                               │
                                               ▼
                                   ┌─────────────────┐
                                   │ LiveKit Server  │
                                   │   (SFU Core)    │
                                   └─────────────────┘
```

#### 2. **LiveKit Server/SFU** (Automático)
```
┌─────────────────┐    Nueva conexión    ┌─────────────────┐
│   Cliente SIP   │ ──────────────────► │ LiveKit Server  │
│  +56975231235   │                      │   (SFU Core)    │
└─────────────────┘                      └─────────────────┘
                                                  │
                                         Crea sala automáticamente
                                         "call-_+56975231235_kwJutxuFvEyA"
                                                  │
                                                  ▼
                                         ┌─────────────────┐
                                         │  Sala Creada    │
                                         │ Busca Agente    │
                                         └─────────────────┘
```

#### 3. **SDK Clients** (Programático)
````python
import livekit

room_service = livekit.RoomService(url, api_key, api_secret)
room_info = await room_service.create_room(
    livekit.CreateRoomRequest(name="my-custom-room")
)
````

#### 4. **REST API** (Manual/Programático)
```bash
curl -X POST "https://test-xzvcu3jl.livekit.cloud/twirp/livekit.RoomService/CreateRoom" \
  -H "Authorization: Bearer <jwt_token>" \
  -H "Content-Type: application/json" \
  -d '{"name": "my-room"}'
```

## Detección y Respuesta a Llamadas

### 6. **📞 Llamada Entrante - Job Request**

Cuando alguien llama, el flujo es:

```
┌─────────────────┐    Llamada SIP    ┌─────────────────┐
│   Teléfono      │ ─────────────────► │ LiveKit Cloud   │
│ +56975231235    │                    │   SFU Server    │
└─────────────────┘                    └─────────────────┘
                                               │
                                    AvailabilityRequest
                                               ▼
┌─────────────────────────────────────────────────────────────────┐
│        Worker recibe job request via WebSocket                 │
│  {"message": "received job request",                           │
│   "job_id": "AJ_AWrDfacJfdLr",                                 │
│   "room_name": "call-_+56975231235_kwJutxuFvEyA"}              │
└─────────────────────────────────────────────────────────────────┘
```

### 7. **Evaluación y Aceptación del Job**

#### Manejo de la disponibilidad:
````python
def _handle_availability(self, msg: agent.AvailabilityRequest) -> None:
    task = self._loop.create_task(self._answer_availability(msg))
    self._tasks.add(task)
    task.add_done_callback(self._tasks.discard)

async def _answer_availability(self, msg: agent.AvailabilityRequest) -> None:
    """Pregunta al usuario si quiere aceptar este job"""

    answered = False

    async def _on_reject() -> None:
        nonlocal answered
        answered = True

        availability_resp = agent.WorkerMessage()
        availability_resp.availability.job_id = msg.job.id
        availability_resp.availability.available = False
        await self._queue_msg(availability_resp)

    async def _on_accept(args: JobAcceptArguments) -> None:
        nonlocal answered
        answered = True

        availability_resp = agent.WorkerMessage()
        availability_resp.availability.job_id = msg.job.id
        availability_resp.availability.available = True
        availability_resp.availability.participant_identity = args.identity
        availability_resp.availability.participant_name = args.name
        availability_resp.availability.participant_metadata = args.metadata
        await self._queue_msg(availability_resp)

        # Esperar asignación del servidor
        wait_assignment = asyncio.Future[agent.JobAssignment]()
        self._pending_assignments[job_req.id] = wait_assignment

        try:
            await asyncio.wait_for(wait_assignment, ASSIGNMENT_TIMEOUT)
        except asyncio.TimeoutError:
            raise AssignmentTimeoutError()

        # Lanzar el job
        job_assign = wait_assignment.result()
        running_info = RunningJobInfo(
            accept_arguments=args,
            job=msg.job,
            url=job_assign.url or self._opts.ws_url,
            token=job_assign.token,
            worker_id=self._id,
        )

        await self._proc_pool.launch_job(running_info)

    # Crear JobRequest para el usuario
    job_req = JobRequest(job=msg.job, on_reject=_on_reject, on_accept=_on_accept)

    logger.info("received job request", extra={
        "job_id": msg.job.id,
        "room_name": msg.job.room.name,
        "agent_name": self._opts.agent_name,
    })

    # Llamar función personalizada del usuario
    @utils.log_exceptions(logger=logger)
    async def _job_request_task() -> None:
        try:
            await self._opts.request_fnc(job_req)  # 🎯 Tu lógica aquí
        except Exception:
            logger.exception("job_request_fnc failed")

        if not answered:
            logger.warning("no answer given, automatically rejecting")
            await _on_reject()

    user_task = self._loop.create_task(_job_request_task())
````

#### Ejemplo de función personalizada:
````python
# En tu código de agente:
async def should_accept_call(job_request: JobRequest) -> None:
    """Decide si el agente debe responder esta llamada"""

    # Log de la llamada entrante
    logger.info(f"Llamada entrante para sala: {job_request.job.room.name}")

    # Lógica personalizada
    current_hour = datetime.now().hour
    if 9 <= current_hour <= 17:  # Solo horario laboral
        await job_request.accept(
            identity="voice-assistant",
            name="Asistente de Voz",
            metadata=json.dumps({"language": "es"})
        )
    else:
        await job_request.reject()
````

## Conexión del Agente a la Llamada

### 8. **Lanzamiento del Agente**

Una vez aceptado el job, se lanza en un proceso separado:

````python
# En _on_accept():
running_info = RunningJobInfo(
    accept_arguments=args,
    job=msg.job,                    # Info de la sala
    url=job_assign.url or self._opts.ws_url,  # URL de LiveKit
    token=job_assign.token,         # Token JWT para conectar
    worker_id=self._id,
)

# 🚀 LANZAR EN PROCESO SEPARADO
await self._proc_pool.launch_job(running_info)

# Log: {"message": "initializing process", "pid": 67201}
````

### 9. **Conexión Real del Agente**

El Worker **NO se conecta directamente** a la llamada. En su lugar:

1. **Worker lanza un proceso separado**
2. **Ese proceso ejecuta tu `entrypoint_fnc`**
3. **Dentro de tu función, TÚ haces la conexión** usando `JobContext.connect()`

#### Secuencia de conexión:
```
┌─────────────────┐   Job Request    ┌─────────────────┐
│ LiveKit Server  │ ──────────────► │     Worker      │
│                 │                  │   (Main Proc)   │
└─────────────────┘                  └─────────────────┘
        ▲                                      │
        │                                      │ launch_job()
        │                                      ▼
        │                            ┌─────────────────┐
        │                            │   Job Process   │
        │                            │                 │
        │                            │ entrypoint_fnc: │
        │         ┌──────────────────│ my_voice_agent()│
        │         │                  │                 │
        │         │ ctx.connect()    │   ctx = JobCtx  │
        │         │                  │   - url         │
        │         │                  │   - token       │
        │         ▼                  │   - job info    │
        └─── 🔗 CONEXIÓN ────────────┘                 │
            WebRTC/LiveKit                              │
            Audio/Video Stream                          │
                                                        ▼
                                              Conversación Activa
```

#### Implementación en tu entrypoint:
````python
async def my_voice_agent(ctx: JobContext):  # ← Tu función entrypoint
    # 🎯 AQUÍ ES DONDE REALMENTE SE CONECTA A LA LLAMADA
    room = await ctx.connect(
        # ctx internamente usa el token y URL del running_info
        # para conectarse a la sala específica de la llamada
    )

    # Ahora el agente está conectado a la llamada
    print(f"Conectado a la sala: {room.name}")
    print(f"Participantes: {list(room.participants.keys())}")

    # Configurar componentes de voz
    stt = openai.realtime.RealtimeSTT()
    llm = openai.realtime.RealtimeLLM()
    tts = openai.realtime.RealtimeTTS()

    # Manejar conversación
    await conversation.handle_participant(participant)
````

#### Implementación interna de JobContext.connect():
````python
# En job.py (aproximadamente)
class JobContext:
    def __init__(self, running_info: RunningJobInfo):
        self._running_info = running_info

    async def connect(self) -> rtc.Room:
        room = rtc.Room()

        # 🔗 CONEXIÓN REAL A LA SALA
        await room.connect(
            url=self._running_info.url,      # wss://test-xzvcu3jl.livekit.cloud
            token=self._running_info.token,  # JWT con permisos para esa sala específica
        )

        return room
````

### 10. **Proceso del Agente Ejecutándose**

```
┌─────────────────────────────────────────────────────────────────┐
│             Proceso 67201 - Agente de Voz Activo               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  async def my_voice_agent(ctx: JobContext):                     │
│      # 1. Conectar a la sala                                   │
│      room = await ctx.connect()                                 │
│                                                                 │
│      # 2. Configurar componentes                                │
│      stt = openai.realtime.RealtimeSTT()                       │
│      llm = openai.realtime.RealtimeLLM()                       │
│      tts = openai.realtime.RealtimeTTS()                       │
│                                                                 │
│      # 3. Manejar conversación                                  │
│      await conversation.handle_participant(participant)         │
│                                                                 │
│  Estado: Conversando con +56975231235                          │
└─────────────────────────────────────────────────────────────────┘
```

## Gestión de Carga y Estados

### Monitoreo de Carga

````python
class _DefaultLoadCalc:
    def __init__(self) -> None:
        self._m_avg = utils.MovingAverage(5)  # Promedio sobre 2.5s
        self._cpu_monitor = get_cpu_monitor()
        self._thread = threading.Thread(target=self._calc_load, daemon=True)
        self._thread.start()

    def _calc_load(self) -> None:
        while True:
            cpu_p = self._cpu_monitor.cpu_percent(interval=0.5)
            with self._lock:
                self._m_avg.add_sample(cpu_p)

    @classmethod
    def get_load(cls, worker: Worker) -> float:
        if cls._instance is None:
            cls._instance = _DefaultLoadCalc()
        return cls._instance._m_avg.get_avg()
````

### Estados del Worker

````python
class WorkerStatus(Enum):
    WS_AVAILABLE = "available"  # Puede recibir jobs
    WS_FULL = "full"           # Carga completa

async def _update_worker_status(self) -> None:
    job_cnt = len(self.active_jobs)

    if self._draining:
        status = agent.WorkerStatus.WS_FULL
    else:
        load_threshold = _WorkerEnvOption.getvalue(self._opts.load_threshold, self._devmode)
        is_full = self._worker_load >= load_threshold
        status = agent.WorkerStatus.WS_AVAILABLE if not is_full else agent.WorkerStatus.WS_FULL

    update = agent.UpdateWorkerStatus(load=self._worker_load, status=status, job_count=job_cnt)
    msg = agent.WorkerMessage(update_worker=update)
    await self._queue_msg(msg)
````

## Manejo de Mensajes WebSocket

### Worker → Server
- `RegisterWorker`: Registra capacidades y permisos
- `AvailabilityResponse`: Responde si puede tomar un job
- `UpdateWorkerStatus`: Actualiza carga y estado cada 2.5s
- `UpdateJobStatus`: Reporta estado de jobs

### Server → Worker
- `AvailabilityRequest`: Pregunta si puede tomar job
- `JobAssignment`: Asigna job con token y URL
- `JobTermination`: Solicita terminar job específico

````python
async def _recv_task() -> None:
    while True:
        msg = await ws.receive()
        server_msg = agent.ServerMessage()
        server_msg.ParseFromString(msg.data)

        which = server_msg.WhichOneof("message")
        if which == "availability":
            self._handle_availability(server_msg.availability)
        elif which == "assignment":
            self._handle_assignment(server_msg.assignment)
        elif which == "termination":
            await self._handle_termination(server_msg.termination)
````

## Finalización y Cleanup

### 11. **Finalización de la Llamada**

````python
{"message": "closing agent session due to participant disconnect",
 "participant": "sip_+56975231235",
 "reason": "CLIENT_INITIATED"}

async def _handle_termination(self, msg: agent.JobTermination) -> None:
    proc = self._proc_pool.get_by_job_id(msg.job_id)
    if not proc:
        return
    await proc.aclose()

async def drain(self, timeout: int | None = None) -> None:
    """Esperar que terminen todos los jobs activos"""
    logger.info("draining worker", extra={"id": self.id, "timeout": timeout})
    self._draining = True
    await self._update_worker_status()

    async def _join_jobs() -> None:
        for proc in self._proc_pool.processes:
            if proc.running_job:
                await proc.join()

    if timeout:
        await asyncio.wait_for(_join_jobs(), timeout)
    else:
        await _join_jobs()
````

## Configuración y Opciones

### WorkerOptions
````python
@dataclass
class WorkerOptions:
    entrypoint_fnc: Callable[[JobContext], Awaitable[None]]
    """Función principal del agente que maneja la conversación"""

    request_fnc: Callable[[JobRequest], Awaitable[None]] = _default_request_fnc
    """Decide si acepta jobs (por defecto acepta todos)"""

    load_fnc: Callable[[Worker], float] = _DefaultLoadCalc.get_load
    """Calcula carga del worker (CPU por defecto)"""

    job_executor_type: JobExecutorType = _default_job_executor_type
    """PROCESS o THREAD (PROCESS por defecto en Linux/Mac)"""

    load_threshold: float = 0.7  # En producción
    """Umbral de carga máxima antes de marcar como FULL"""

    num_idle_processes: int = min(math.ceil(cpu_count), 4)
    """Número de procesos idle a mantener"""

    permissions: WorkerPermissions = WorkerPermissions()
    """Permisos del agente en la sala"""

    ws_url: str = "ws://localhost:7880"
    """URL del servidor LiveKit"""

    api_key: str | None = None
    """Clave API de LiveKit"""

    api_secret: str | None = None
    """Secret API de LiveKit"""
````

### WorkerPermissions
````python
@dataclass
class WorkerPermissions:
    can_publish: bool = True          # Puede publicar audio/video
    can_subscribe: bool = True        # Puede escuchar audio/video
    can_publish_data: bool = True     # Puede enviar datos
    can_update_metadata: bool = True  # Puede actualizar metadata
    can_publish_sources: list[models.TrackSource] = []  # Fuentes específicas
    hidden: bool = False              # Participante oculto
````

## Errores Comunes y Soluciones

### 1. **Warnings del Log**
````python
# Warning: Texto recibido en modalidad de audio
{"message": "Text response received from OpenAI Realtime API in audio modality.", "level": "WARNING"}

# Error: Mixing de modalidades
{"message": "Text message received from Realtime API with audio modality", "level": "ERROR"}
````

**Solución**: Configurar fallback TTS o usar modalidad text+TTS consistentemente.

### 2. **Assignment Timeout**
````python
{"message": "assignment for job timed out", "level": "WARNING"}
````

**Causa**: El Worker aceptó el job pero no recibió asignación del servidor en 7.5s.
**Solución**: Verificar conectividad y estado del servidor.

### 3. **Process Memory Limit**
````python
job_memory_warn_mb: float = 500    # Warning en 500MB
job_memory_limit_mb: float = 0     # Sin límite (0 = disabled)
````

## Resumen del Flujo Completo

### Estados del Worker:
1. **Starting** → Inicializando componentes
2. **Registered** → Conectado a LiveKit Cloud
3. **Available** → Esperando llamadas
4. **Busy** → Procesando llamada(s)
5. **Draining** → Finalizando jobs antes de cerrar

### Secuencia Completa:
```
Comando → Worker Init → Process Pool → WebSocket → Registro → Listening
    ↓
📞 Llamada → Job Request → Evaluación → Aceptación → Assignment
    ↓
Nuevo Proceso → Agente Conecta → Conversación → Desconexión
```

### Puntos Clave:
- **Worker**: Dispatcher inteligente, NO maneja conversaciones directamente
- **Process Pool**: Mantiene procesos idle para respuesta rápida
- **JobContext.connect()**: Punto real de conexión a la llamada
- **Salas**: Creadas por SIP Gateway/Server, NO por el Worker
- **Carga**: Monitoreada continuamente para auto-scaling
- **WebSocket**: Comunicación bidireccional con LiveKit Cloud

El Worker actúa como un **operador telefónico inteligente** que mantiene una flota de agentes listos para responder llamadas entrantes según las reglas de negocio que definas.
