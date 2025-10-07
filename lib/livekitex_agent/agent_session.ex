defmodule LivekitexAgent.AgentSession do
  @moduledoc """
  The runtime that orchestrates all components into a working voice agent.

  AgentSession handles:
  - Media streams coordination
  - Speech/LLM components integration
  - Tool orchestration
  - Turn detection and endpointing
  - Interruption handling
  - Multi-step tool calls
  - Audio, video, and text I/O management
  - Real-time voice agent lifecycle
  - Comprehensive event callbacks system

  ## Event Callbacks System

  The AgentSession provides a comprehensive event callback system that allows you to
  monitor and react to various session events. Events are emitted throughout the
  session lifecycle and can be handled by registering callback functions.

  ### Available Events

  #### Session Lifecycle Events
  - `:session_started` - Session initialization complete
  - `:session_stopped` - Session terminated
  - `:state_changed` - Session state transition

  #### Audio Processing Events
  - `:audio_received` - Raw audio data received from user
  - `:audio_streamed` - Audio streamed to realtime server
  - `:audio_output` - Audio output generated for playback
  - `:tts_audio` - TTS audio chunk generated
  - `:tts_complete` - TTS synthesis completed

  #### Speech Recognition Events
  - `:stt_result` - Speech-to-text transcription result
  - `:vad_speech_start` - Voice activity detected (speech started)
  - `:vad_speech_end` - Voice activity ended (speech stopped)

  #### Conversation Events
  - `:text_received` - Text input received from user
  - `:response_generated` - Agent response generated
  - `:speaking_started` - Agent started speaking
  - `:turn_started` - New conversation turn started
  - `:turn_completed` - Conversation turn completed

  #### Tool Execution Events
  - `:tool_called` - Function tool invoked
  - `:tool_completed` - Function tool execution completed
  - `:tool_error` - Function tool execution failed

  #### Interruption Events
  - `:interrupted` - Session was interrupted
  - `:response_cancelled` - Response generation cancelled

  #### Participant Events
  - `:participant_updated` - Participant information updated
  - `:participant_removed` - Participant removed from session

  #### LiveKit Integration Events
  - `:room_id_updated` - LiveKit room ID changed
  - `:realtime_event` - Raw realtime server event
  - `:realtime_closed` - Realtime connection closed

  #### Callback Management Events
  - `:callback_registered` - Event callback registered
  - `:callbacks_registered` - Multiple callbacks registered
  - `:callback_unregistered` - Event callback removed

  ### Callback Function Formats

  Event callbacks can be functions with 1 or 2 arguments:

      # Single argument (receives event data)
      callback_fun = fn data -> IO.puts("Event: #{inspect(data)}") end

      # Two arguments (receives event type and data)
      callback_fun = fn event_type, data ->
        IO.puts("#{event_type}: #{inspect(data)}")
      end

  ### Example Usage

      # Register callbacks during session creation
      {:ok, session} = AgentSession.start_link(
        agent: agent,
        event_callbacks: %{
          session_started: fn _evt, data ->
            Logger.info("Session started: #{data.session_id}")
          end,
          text_received: fn _evt, data ->
            Logger.info("User said: #{data.text}")
          end,
          response_generated: fn _evt, data ->
            Logger.info("Agent replied: #{data.text}")
          end
        }
      )

      # Register additional callbacks at runtime
      AgentSession.register_callback(session, :interrupted, fn _evt, _data ->
        Logger.warn("Session was interrupted!")
      end)

      # Register multiple callbacks at once
      AgentSession.register_callbacks(session, %{
        tool_called: fn _evt, data -> track_tool_usage(data.tool_name) end,
        tool_completed: fn _evt, data -> log_tool_result(data.result) end
      })
  """

  use GenServer
  require Logger

  defstruct [
    :agent,
    :session_id,
    :realtime_client,
    :llm_client,
    :tts_client,
    :stt_client,
    :vad_client,
    :media_streams,
    :chat_context,
    :current_turn,
    :tool_registry,
    :event_callbacks,
    :state,
    :metrics,
    :user_data,
    :started_at,
    :audio_buffer,
    :input_audio_buffer,
    :conversation_state,
    :turn_history,
    :last_activity_at,
    :room_id,
    :participants,
    :created_at
  ]

  @type session_state :: :idle | :listening | :processing | :speaking | :interrupted | :stopped

  @type t :: %__MODULE__{
          agent: LivekitexAgent.Agent.t(),
          session_id: String.t(),
          llm_client: pid() | nil,
          realtime_client: pid() | nil,
          tts_client: pid() | nil,
          stt_client: pid() | nil,
          vad_client: pid() | nil,
          media_streams: map(),
          chat_context: list(),
          current_turn: map() | nil,
          tool_registry: map(),
          event_callbacks: map(),
          state: session_state(),
          metrics: map(),
          user_data: map(),
          started_at: DateTime.t(),
          audio_buffer: list(),
          conversation_state: map(),
          turn_history: list(),
          last_activity_at: DateTime.t(),
          room_id: String.t() | nil,
          participants: map(),
          created_at: DateTime.t() | nil
        }

  @doc """
  Starts a new agent session.

  ## Options
  - `:agent` - The agent configuration to use
  - `:llm_client` - Language model client pid
  - `:tts_client` - Text-to-speech client pid
  - `:stt_client` - Speech-to-text client pid
  - `:vad_client` - Voice activity detection client pid
  - `:event_callbacks` - Map of event callbacks

  ## Example
      iex> {:ok, session} = LivekitexAgent.AgentSession.start_link(
      ...>   agent: agent,
      ...>   llm_client: llm_pid,
      ...>   tts_client: tts_pid
      ...> )
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Processes incoming audio data from the user.
  """
  def process_audio(session_pid, audio_data) do
    GenServer.cast(session_pid, {:process_audio, audio_data})
  end

  @doc """
  Processes text input from the user.
  """
  def process_text(session_pid, text) do
    GenServer.cast(session_pid, {:process_text, text})
  end

  @doc """
  Send raw PCM16 audio chunk to realtime server (if configured);
  falls back to internal STT pipeline.
  """
  def stream_audio(session_pid, pcm16_binary) when is_binary(pcm16_binary) do
    GenServer.cast(session_pid, {:stream_audio, pcm16_binary})
  end

  @doc """
  Commit audio input turn on realtime server (if configured).
  """
  def commit_audio(session_pid) do
    GenServer.cast(session_pid, :commit_audio)
  end

  @doc """
  Send a text prompt directly to realtime server and request a response (if configured);
  otherwise routes through LLM.
  """
  def send_text(session_pid, text) when is_binary(text) do
    GenServer.cast(session_pid, {:send_text, text})
  end

  @doc """
  Cancel current realtime response (if configured).
  """
  def cancel_response(session_pid) do
    GenServer.cast(session_pid, :cancel_response)
  end

  @doc """
  Interrupts the current agent response.
  """
  def interrupt(session_pid) do
    GenServer.cast(session_pid, :interrupt)
  end

  @doc """
  Gets the current session state.
  """
  def get_state(session_pid) do
    GenServer.call(session_pid, :get_state)
  end

  @doc """
  Gets session metrics and usage statistics.
  """
  def get_metrics(session_pid) do
    GenServer.call(session_pid, :get_metrics)
  end

  @doc """
  Registers an event callback for the session.
  """
  def register_callback(session_pid, event, callback_fun) do
    GenServer.call(session_pid, {:register_callback, event, callback_fun})
  end

  @doc """
  Registers multiple event callbacks at once.
  """
  def register_callbacks(session_pid, callbacks) when is_map(callbacks) do
    GenServer.call(session_pid, {:register_callbacks, callbacks})
  end

  @doc """
  Unregisters an event callback.
  """
  def unregister_callback(session_pid, event) do
    GenServer.call(session_pid, {:unregister_callback, event})
  end

  @doc """
  Lists all registered event callbacks.
  """
  def list_callbacks(session_pid) do
    GenServer.call(session_pid, :list_callbacks)
  end

  @doc """
  Emits a custom event to the session's event handlers.
  """
  def emit_custom_event(session_pid, event_type, data) do
    GenServer.cast(session_pid, {:emit_custom_event, event_type, data})
  end

  @doc """
  Gets the conversation state and history.
  """
  def get_conversation_state(session_pid) do
    GenServer.call(session_pid, :get_conversation_state)
  end

  @doc """
  Gets the current turn information.
  """
  def get_current_turn(session_pid) do
    GenServer.call(session_pid, :get_current_turn)
  end

  @doc """
  Gets the turn history for the session.
  """
  def get_turn_history(session_pid) do
    GenServer.call(session_pid, :get_turn_history)
  end

  @doc """
  Adds custom data to the conversation state.
  """
  def add_conversation_data(session_pid, key, value) do
    GenServer.call(session_pid, {:add_conversation_data, key, value})
  end

  @doc """
  Saves conversation state to persistent storage.

  ## Options
  - `:storage_backend` - Storage backend (:ets, :file, :database) (default: :ets)
  - `:storage_path` - Path for file storage (default: "./conversation_states")
  - `:compression` - Enable compression for storage (default: true)
  - `:ttl` - Time-to-live for stored data in seconds (default: 86400 - 24 hours)
  """
  def save_conversation_state(session_pid, opts \\ []) do
    GenServer.call(session_pid, {:save_conversation_state, opts})
  end

  @doc """
  Loads conversation state from persistent storage.

  ## Parameters
  - `session_id` - Session identifier to load
  - `opts` - Storage options (same as save_conversation_state)

  Returns `{:ok, conversation_data}` or `{:error, reason}`.
  """
  def load_conversation_state(session_id, opts \\ []) do
    LivekitexAgent.AgentSession.StateManager.load_state(session_id, opts)
  end

  @doc """
  Restores a session from persisted conversation state.

  This creates a new session and restores its state from persistent storage.
  """
  def restore_session(session_id, opts \\ []) do
    case load_conversation_state(session_id, opts) do
      {:ok, conversation_data} ->
        session_opts = Keyword.merge(opts, [
          session_id: session_id,
          restore_data: conversation_data
        ])
        start_session(session_opts)

      {:error, reason} ->
        {:error, {:restore_failed, reason}}
    end
  end

  @doc """
  Updates participant information for the session.
  """
  def update_participant(session_pid, participant_id, participant_data) do
    GenServer.call(session_pid, {:update_participant, participant_id, participant_data})
  end

  @doc """
  Removes a participant from the session.
  """
  def remove_participant(session_pid, participant_id) do
    GenServer.call(session_pid, {:remove_participant, participant_id})
  end

  @doc """
  Sets the room ID for the session (LiveKit integration).
  """
  def set_room_id(session_pid, room_id) do
    GenServer.call(session_pid, {:set_room_id, room_id})
  end

  @doc """
  Stops the agent session.
  """
  def stop(session_pid) do
    GenServer.stop(session_pid)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    agent = Keyword.fetch!(opts, :agent)

    # Initialize StateManager if not already done
    LivekitexAgent.AgentSession.StateManager.init()

    # Check for restore data
    restore_data = Keyword.get(opts, :restore_data)

    session = if restore_data do
      # Restore from persisted state
      Logger.info("Restoring session from persisted state: #{restore_data.session_id}")

      %__MODULE__{
        agent: agent,
        session_id: restore_data.session_id,
        realtime_client: nil,
        llm_client: Keyword.get(opts, :llm_client),
        tts_client: Keyword.get(opts, :tts_client),
        stt_client: Keyword.get(opts, :stt_client),
        vad_client: Keyword.get(opts, :vad_client),
        media_streams: %{},
        chat_context: [],
        current_turn: nil,
        tool_registry: build_tool_registry(agent.tools),
        event_callbacks: Keyword.get(opts, :event_callbacks, %{}),
        state: :idle,
        metrics: init_metrics(),
        user_data: Keyword.get(opts, :user_data, %{}),
        started_at: restore_data.created_at || DateTime.utc_now(),
        audio_buffer: [],
        input_audio_buffer: [],
        conversation_state: restore_data.conversation_state || init_conversation_state(),
        turn_history: restore_data.turn_history || [],
        last_activity_at: restore_data.updated_at || DateTime.utc_now(),
        room_id: restore_data.room_id || Keyword.get(opts, :room_id),
        participants: restore_data.participants || %{},
        created_at: restore_data.created_at
      }
    else
      # Create new session
      %__MODULE__{
        agent: agent,
        session_id: Keyword.get(opts, :session_id) || generate_session_id(),
        realtime_client: nil,
        llm_client: Keyword.get(opts, :llm_client),
        tts_client: Keyword.get(opts, :tts_client),
        stt_client: Keyword.get(opts, :stt_client),
        vad_client: Keyword.get(opts, :vad_client),
        media_streams: %{},
        chat_context: [],
        current_turn: nil,
        tool_registry: build_tool_registry(agent.tools),
        event_callbacks: Keyword.get(opts, :event_callbacks, %{}),
        state: :idle,
        metrics: init_metrics(),
        user_data: Keyword.get(opts, :user_data, %{}),
        started_at: DateTime.utc_now(),
        audio_buffer: [],
        input_audio_buffer: [],
        conversation_state: init_conversation_state(),
        turn_history: [],
        last_activity_at: DateTime.utc_now(),
        room_id: Keyword.get(opts, :room_id),
        participants: %{},
        created_at: DateTime.utc_now()
      }
    end

    Logger.info("Agent session started: #{session.session_id}")
    emit_event(session, :session_started, %{session_id: session.session_id})

    # Start VAD/STT/TTS plugin processes if configured with module & opts
    session =
      session
      |> maybe_start_vad(agent.vad_config)
      |> maybe_start_stt(agent.stt_config)
      |> maybe_start_tts(agent.tts_config)

    # Optionally start realtime client if :realtime_config is provided
    case Keyword.get(opts, :realtime_config) do
      %{} = rt_cfg ->
        {:ok, rt_pid} =
          LivekitexAgent.RealtimeWSClient.start_link(parent: self(), config: rt_cfg)

        {:ok, %{session | realtime_client: rt_pid}}

      _ ->
        {:ok, session}
    end
  end

  @impl true
  def handle_cast({:process_audio, audio_data}, session) do
    Logger.debug("Processing audio data: #{byte_size(audio_data)} bytes")

    # Update state to listening if idle and track activity
    session = if session.state == :idle do
      %{session | state: :listening, last_activity_at: DateTime.utc_now()}
    else
      %{session | last_activity_at: DateTime.utc_now()}
    end

    # Route audio to VAD if present
    if session.vad_client do
      send(session.vad_client, {:process_audio, audio_data})
    end

    # Buffer input audio for potential utterance assembly (reverse order for O(1) prepend)
    session = %{session | input_audio_buffer: [audio_data | session.input_audio_buffer]}

    # Update metrics
    updated_metrics = %{session.metrics |
      audio_segments_processed: session.metrics.audio_segments_processed + 1
    }

    session = %{session | metrics: updated_metrics}

    # Process audio through STT if available
    case session.stt_client do
      nil ->
        Logger.warning("No STT client available for audio processing")
        {:noreply, session}

      stt_pid ->
        # Send audio to STT client
        send(stt_pid, {:process_audio, audio_data})
        emit_event(session, :audio_received, %{size: byte_size(audio_data)})
        {:noreply, session}
    end
  end

  @impl true
  def handle_cast({:stream_audio, pcm16}, session) do
    case session.realtime_client do
      nil ->
        # Fallback to local audio processing
        handle_cast({:process_audio, pcm16}, session)

      rt_pid ->
        LivekitexAgent.RealtimeWSClient.send_audio_chunk(rt_pid, pcm16)
        emit_event(session, :audio_streamed, %{size: byte_size(pcm16)})
        {:noreply, if(session.state == :idle, do: %{session | state: :listening}, else: session)}
    end
  end

  @impl true
  def handle_cast(:commit_audio, session) do
    if session.realtime_client do
      LivekitexAgent.RealtimeWSClient.commit_input(session.realtime_client)
      # Ask for a server-side response
      LivekitexAgent.RealtimeWSClient.request_response(session.realtime_client)
    end

    {:noreply, session}
  end

  @impl true
  def handle_cast({:send_text, text}, session) do
    case session.realtime_client do
      nil ->
        handle_cast({:process_text, text}, session)

      rt_pid ->
        LivekitexAgent.RealtimeWSClient.send_text(rt_pid, text)
        {:noreply, %{session | state: :processing}}
    end
  end

  @impl true
  def handle_cast(:cancel_response, session) do
    if session.realtime_client do
      LivekitexAgent.RealtimeWSClient.cancel_response(session.realtime_client)
    end

    {:noreply, session}
  end

  @impl true
  def handle_cast({:process_text, text}, session) do
    Logger.info("Processing text: #{text}")

    session = %{session | state: :processing, last_activity_at: DateTime.utc_now()}
    emit_event(session, :text_received, %{text: text})

    # Create new turn
    turn_id = generate_turn_id()
    new_turn = %{
      turn_id: turn_id,
      type: :text,
      input: text,
      started_at: DateTime.utc_now(),
      completed_at: nil,
      response: nil,
      tool_calls: [],
      metadata: %{}
    }

    # Emit turn started event
    emit_event(session, :turn_started, %{
      turn_id: turn_id,
      type: :text,
      input: text
    })

    # Add user message to chat context
    updated_context = session.chat_context ++ [%{role: "user", content: text}]

    # Update metrics
    updated_metrics = %{session.metrics |
      messages_processed: session.metrics.messages_processed + 1,
      total_text_characters: session.metrics.total_text_characters + String.length(text)
    }

    session = %{session |
      chat_context: updated_context,
      current_turn: new_turn,
      metrics: updated_metrics
    }

    # Process through LLM
    case session.llm_client do
      nil ->
        Logger.warning("No LLM client available for text processing")
        {:noreply, %{session | state: :idle}}

      llm_pid ->
        send(llm_pid, {:process_message, text, session.chat_context, session.agent.instructions})
        {:noreply, session}
    end
  end

  @impl true
  def handle_cast(:interrupt, session) do
    Logger.info("Interrupting current session")

    # Stop current TTS if speaking
    if session.state == :speaking and session.tts_client do
      send(session.tts_client, :stop)
    end

    # Update metrics and track current turn as interrupted
    updated_metrics = %{session.metrics |
      interruptions: session.metrics.interruptions + 1
    }

    # If there's a current turn, mark it as interrupted and add to history
    turn_history = if session.current_turn do
      interrupted_turn = %{session.current_turn |
        completed_at: DateTime.utc_now(),
        metadata: Map.put(session.current_turn.metadata, :interrupted, true)
      }
      session.turn_history ++ [interrupted_turn]
    else
      session.turn_history
    end

    session = %{session |
      state: :interrupted,
      current_turn: nil,
      turn_history: turn_history,
      metrics: updated_metrics,
      last_activity_at: DateTime.utc_now()
    }

    emit_event(session, :interrupted, %{})

    {:noreply, session}
  end

  @impl true
  def handle_call(:get_state, _from, session) do
    state_info = %{
      session_id: session.session_id,
      state: session.state,
      chat_context_length: length(session.chat_context),
      started_at: session.started_at,
      uptime: DateTime.diff(DateTime.utc_now(), session.started_at, :second)
    }

    {:reply, state_info, session}
  end

  @impl true
  def handle_call(:get_metrics, _from, session) do
    {:reply, session.metrics, session}
  end

  @impl true
  def handle_call({:register_callback, event, callback_fun}, _from, session) do
    updated_callbacks = Map.put(session.event_callbacks, event, callback_fun)
    session = %{session | event_callbacks: updated_callbacks}
    emit_event(session, :callback_registered, %{event: event})
    {:reply, :ok, session}
  end

  @impl true
  def handle_call({:register_callbacks, callbacks}, _from, session) do
    updated_callbacks = Map.merge(session.event_callbacks, callbacks)
    session = %{session | event_callbacks: updated_callbacks}
    emit_event(session, :callbacks_registered, %{events: Map.keys(callbacks)})
    {:reply, :ok, session}
  end

  @impl true
  def handle_call({:unregister_callback, event}, _from, session) do
    updated_callbacks = Map.delete(session.event_callbacks, event)
    session = %{session | event_callbacks: updated_callbacks}
    emit_event(session, :callback_unregistered, %{event: event})
    {:reply, :ok, session}
  end

  @impl true
  def handle_call(:list_callbacks, _from, session) do
    callback_info = %{
      registered_events: Map.keys(session.event_callbacks),
      callback_count: map_size(session.event_callbacks)
    }
    {:reply, callback_info, session}
  end

  @impl true
  def handle_cast({:emit_custom_event, event_type, data}, session) do
    emit_event(session, event_type, data)
    {:noreply, session}
  end

  @impl true
  def handle_call(:get_conversation_state, _from, session) do
    conversation_info = %{
      session_id: session.session_id,
      state: session.state,
      chat_context: session.chat_context,
      conversation_state: session.conversation_state,
      turn_count: length(session.turn_history),
      last_activity_at: session.last_activity_at,
      participants: session.participants,
      room_id: session.room_id
    }
    {:reply, conversation_info, session}
  end

  @impl true
  def handle_call(:get_current_turn, _from, session) do
    {:reply, session.current_turn, session}
  end

  @impl true
  def handle_call(:get_turn_history, _from, session) do
    {:reply, session.turn_history, session}
  end

  @impl true
  def handle_call({:add_conversation_data, key, value}, _from, session) do
    updated_state = Map.put(session.conversation_state, key, value)
    session = %{session | conversation_state: updated_state, last_activity_at: DateTime.utc_now()}
    {:reply, :ok, session}
  end

  @impl true
  def handle_call({:update_participant, participant_id, participant_data}, _from, session) do
    updated_participants = Map.put(session.participants, participant_id, participant_data)
    session = %{session | participants: updated_participants, last_activity_at: DateTime.utc_now()}
    emit_event(session, :participant_updated, %{participant_id: participant_id, data: participant_data})
    {:reply, :ok, session}
  end

  @impl true
  def handle_call({:save_conversation_state, opts}, _from, session) do
    case LivekitexAgent.AgentSession.StateManager.save_state(session, opts) do
      {:ok, saved_data} ->
        emit_event(session, :conversation_state_saved, %{
          session_id: session.session_id,
          saved_at: DateTime.utc_now(),
          storage_backend: Keyword.get(opts, :storage_backend, :ets)
        })
        {:reply, {:ok, saved_data}, session}

      {:error, reason} ->
        Logger.error("Failed to save conversation state for session #{session.session_id}: #{inspect(reason)}")
        emit_event(session, :conversation_state_save_failed, %{
          session_id: session.session_id,
          reason: reason
        })
        {:reply, {:error, reason}, session}
    end
  end

  @impl true
  def handle_call({:remove_participant, participant_id}, _from, session) do
    updated_participants = Map.delete(session.participants, participant_id)
    session = %{session | participants: updated_participants, last_activity_at: DateTime.utc_now()}
    emit_event(session, :participant_removed, %{participant_id: participant_id})
    {:reply, :ok, session}
  end

  @impl true
  def handle_call({:set_room_id, room_id}, _from, session) do
    session = %{session | room_id: room_id, last_activity_at: DateTime.utc_now()}
    emit_event(session, :room_id_updated, %{room_id: room_id})
    {:reply, :ok, session}
  end

  @impl true
  def handle_info({:llm_response, response}, session) do
    Logger.info("Received LLM response")

    # Check if response contains tool calls
    case extract_tool_calls(response) do
      [] ->
        # Regular text response - send to TTS
        handle_text_response(session, response)

      tool_calls ->
        # Execute tool calls
        handle_tool_calls(session, tool_calls)
    end
  end

  @impl true
  def handle_info({:realtime_event, event}, session) do
    # Route relevant realtime events to the proper components.
    case event do
      %{"type" => "socket.connected"} ->
        # Initialize the remote session with our agent instructions and defaults
        if session.realtime_client do
          LivekitexAgent.RealtimeWSClient.send_event(session.realtime_client, %{
            "type" => "session.update",
            "session" => %{
              "instructions" => session.agent.instructions,
              "modalities" => ["audio", "text"],
              "voice" => "alloy"
            }
          })
        end

        {:noreply, session}

      %{"type" => type} when is_binary(type) ->
        cond do
          String.starts_with?(type, "response.") ->
            handle_realtime_response_event(event, session)

          String.starts_with?(type, "input_audio_buffer.") ->
            emit_event(session, :audio_ack, event)
            {:noreply, session}

          true ->
            emit_event(session, :realtime_event, event)
            {:noreply, session}
        end

      # Binary audio frames from server (already base64-decoded by client)
      %{"type" => "binary", "payload" => bin} when is_binary(bin) ->
        # Buffer audio and attempt playback in small chunks
        # For simplicity, append; real implementation should chunk by duration
        session = %{session | audio_buffer: [IO.iodata_to_binary([session.audio_buffer, bin])]}
        emit_event(session, :audio_output, %{size: byte_size(bin)})
        {:noreply, session}

      other ->
        emit_event(session, :realtime_event, other)
        {:noreply, session}
    end
  end

  @impl true
  def handle_info({:realtime_closed, reason}, session) do
    emit_event(session, :realtime_closed, %{reason: inspect(reason)})
    {:noreply, %{session | realtime_client: nil}}
  end

  @impl true
  def handle_info({:stt_result, text}, session) do
    Logger.info("STT result: #{text}")
    emit_event(session, :stt_result, %{text: text})

    # Process the transcribed text
    handle_cast({:process_text, text}, session)
  end

  @impl true
  def handle_info({:vad_event, :speech_start}, session) do
    emit_event(session, :vad_speech_start, %{})
    {:noreply, %{session | state: :listening}}
  end

  @impl true
  def handle_info({:vad_event, :speech_end}, session) do
    emit_event(session, :vad_speech_end, %{})

    # If using realtime server, commit the input buffer and request a response
    if session.realtime_client do
      LivekitexAgent.RealtimeWSClient.commit_input(session.realtime_client)
      LivekitexAgent.RealtimeWSClient.request_response(session.realtime_client)
      {:noreply, session}
    else
      # Otherwise, hand the buffered audio to STT as a complete utterance
      case session.stt_client do
        nil ->
          {:noreply, %{session | audio_buffer: []}}

        stt ->
          audio = IO.iodata_to_binary(Enum.reverse(session.input_audio_buffer))
          send(stt, {:process_utterance, audio})
          {:noreply, %{session | input_audio_buffer: []}}
      end
    end
  end

  @impl true
  def handle_info({:tts_complete, audio_data}, session) do
    Logger.info("TTS synthesis complete")
    emit_event(session, :tts_complete, %{audio_size: byte_size(audio_data)})

    session = %{session | state: :idle}
    {:noreply, session}
  end

  @impl true
  def handle_info({:tts_audio, chunk}, session) when is_binary(chunk) do
    emit_event(session, :tts_audio, %{size: byte_size(chunk)})
    # Buffer for playback (shared buffer used for realtime audio as well)
    {:noreply, %{session | audio_buffer: [IO.iodata_to_binary([session.audio_buffer, chunk])]}}
  end

  @impl true
  def handle_info({:tool_result, tool_name, result}, session) do
    Logger.info("Tool #{tool_name} completed with result")

    # Emit tool completed event
    emit_event(session, :tool_completed, %{
      tool_name: tool_name,
      result: result,
      timestamp: DateTime.utc_now()
    })

    # Add tool result to chat context and continue conversation
    updated_context = session.chat_context ++ [%{role: "tool", name: tool_name, content: result}]
    session = %{session | chat_context: updated_context}

    # Continue with LLM processing
    case session.llm_client do
      nil ->
        {:noreply, %{session | state: :idle}}

      llm_pid ->
        send(llm_pid, {:continue_with_context, session.chat_context})
        {:noreply, session}
    end
  end

  @impl true
  def handle_info({:tool_error, tool_name, reason}, session) do
    Logger.error("Tool #{tool_name} failed with error: #{inspect(reason)}")

    # Emit tool error event
    emit_event(session, :tool_error, %{
      tool_name: tool_name,
      error: reason,
      timestamp: DateTime.utc_now()
    })

    # Add tool error to chat context for LLM to handle
    error_message = "Tool #{tool_name} failed: #{inspect(reason)}"
    updated_context = session.chat_context ++ [%{role: "tool", name: tool_name, content: error_message}]
    session = %{session | chat_context: updated_context}

    # Continue with LLM processing to handle the error
    case session.llm_client do
      nil ->
        {:noreply, %{session | state: :idle}}

      llm_pid ->
        send(llm_pid, {:continue_with_context, session.chat_context})
        {:noreply, session}
    end
  end

  # Private functions

  # Start plugin helpers
  defp maybe_start_vad(session, %{} = cfg) do
    cond do
      session.vad_client ->
        session

      is_atom(cfg[:module]) ->
        {:ok, pid} = cfg.module.start_link(parent: self(), opts: cfg[:opts] || [])
        %{session | vad_client: pid}

      true ->
        session
    end
  end

  defp maybe_start_vad(session, _), do: session

  defp maybe_start_stt(session, %{} = cfg) do
    cond do
      session.stt_client ->
        session

      is_atom(cfg[:module]) ->
        {:ok, pid} = cfg.module.start_link(parent: self(), opts: cfg[:opts] || [])
        %{session | stt_client: pid}

      true ->
        session
    end
  end

  defp maybe_start_stt(session, _), do: session

  defp maybe_start_tts(session, %{} = cfg) do
    cond do
      session.tts_client ->
        session

      is_atom(cfg[:module]) ->
        {:ok, pid} = cfg.module.start_link(parent: self(), opts: cfg[:opts] || [])
        %{session | tts_client: pid}

      true ->
        session
    end
  end

  defp maybe_start_tts(session, _), do: session

  defp generate_session_id do
    :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
  end

  defp generate_turn_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp build_tool_registry(tools) do
    Enum.reduce(tools, %{}, fn tool, acc ->
      Map.put(acc, tool, %{name: tool, module: tool})
    end)
  end

  defp init_metrics do
    %{
      messages_processed: 0,
      audio_segments_processed: 0,
      tool_calls_executed: 0,
      interruptions: 0,
      total_audio_duration: 0.0,
      total_text_characters: 0
    }
  end

  defp init_conversation_state do
    %{
      intent: nil,
      context: %{},
      topic: nil,
      user_preferences: %{},
      conversation_stage: :initial,
      custom_data: %{}
    }
  end

  defp emit_event(session, event_type, data) do
    case Map.get(session.event_callbacks, event_type) do
      nil ->
        :ok

      callback_fun when is_function(callback_fun, 2) ->
        safe_invoke(callback_fun, event_type, data)

      callback_fun when is_function(callback_fun, 1) ->
        safe_invoke(fn d -> callback_fun.(d) end, data)

      _ ->
        :ok
    end
  end

  defp safe_invoke(fun, a, b) do
    try do
      fun.(a, b)
    rescue
      error ->
        Logger.error("Error in event callback for #{inspect(a)}: #{Exception.message(error)}")
    end
  end

  defp safe_invoke(fun, a) do
    try do
      fun.(a)
    rescue
      error -> Logger.error("Error in event callback: #{Exception.message(error)}")
    end
  end

  # Accepts several shapes:
  # - Map with "tool_calls" or :tool_calls
  # - Map with "function_call" or :function_call (single call)
  # - OpenAI-style tool_calls: [%{"type" => "function", "function" => %{name, arguments}}]
  # - A JSON string containing any of the above
  # - A bare list of calls
  defp extract_tool_calls(%{"tool_calls" => calls}), do: normalize_calls(calls)
  defp extract_tool_calls(%{tool_calls: calls}), do: normalize_calls(calls)
  defp extract_tool_calls(%{"function_call" => call}), do: normalize_calls([call])
  defp extract_tool_calls(%{function_call: call}), do: normalize_calls([call])
  defp extract_tool_calls(calls) when is_list(calls), do: normalize_calls(calls)

  defp extract_tool_calls(bin) when is_binary(bin) do
    case Jason.decode(bin) do
      {:ok, decoded} -> extract_tool_calls(decoded)
      _ -> []
    end
  end

  defp extract_tool_calls(_), do: []

  defp normalize_calls(calls) do
    calls
    |> List.wrap()
    |> Enum.map(&normalize_tool_call/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_tool_call(%{"name" => name, "arguments" => args}),
    do: %{name: to_string(name), arguments: ensure_map(args)}

  defp normalize_tool_call(%{name: name, arguments: args}) when is_atom(name) or is_binary(name),
    do: %{name: to_string(name), arguments: ensure_map(args)}

  defp normalize_tool_call(%{"function" => %{"name" => name, "arguments" => args}}),
    do: %{name: to_string(name), arguments: ensure_map(args)}

  defp normalize_tool_call(%{function: %{name: name, arguments: args}}),
    do: %{name: to_string(name), arguments: ensure_map(args)}

  defp normalize_tool_call(_), do: nil

  defp ensure_map(%{} = m), do: m

  defp ensure_map(bin) when is_binary(bin) do
    case Jason.decode(bin) do
      {:ok, %{} = m} -> m
      _ -> %{}
    end
  end

  defp handle_text_response(session, response) do
    # Add assistant response to chat context
    updated_context = session.chat_context ++ [%{role: "assistant", content: response}]

    # Complete current turn
    completed_turn = if session.current_turn do
      %{session.current_turn |
        response: response,
        completed_at: DateTime.utc_now()
      }
    else
      nil
    end

    # Emit turn completed event
    if completed_turn do
      emit_event(session, :turn_completed, %{
        turn_id: completed_turn.turn_id,
        type: completed_turn.type,
        input: completed_turn.input,
        response: response,
        duration: DateTime.diff(completed_turn.completed_at, completed_turn.started_at, :millisecond)
      })
    end

    # Add turn to history
    turn_history = if completed_turn do
      session.turn_history ++ [completed_turn]
    else
      session.turn_history
    end

    session = %{session |
      chat_context: updated_context,
      state: :speaking,
      current_turn: nil,
      turn_history: turn_history,
      last_activity_at: DateTime.utc_now()
    }

    # Send to TTS if available
    case session.tts_client do
      nil ->
        Logger.warning("No TTS client available")
        emit_event(session, :response_generated, %{text: response})
        {:noreply, %{session | state: :idle}}

      tts_pid ->
        send(tts_pid, {:synthesize, response})
        emit_event(session, :speaking_started, %{text: response})
        emit_event(session, :response_generated, %{text: response})
        {:noreply, session}
    end
  end

  defp handle_realtime_response_event(%{"type" => type} = event, session) do
    cond do
      String.ends_with?(type, ".delta") ->
        # Streamed delta: could contain text or audio
        emit_event(session, :response_delta, event)
        {:noreply, %{session | state: :speaking}}

      # Map audio transcript events to our generic callbacks
      type == "response.audio_transcript.delta" ->
        emit_event(session, :response_delta, event)
        {:noreply, %{session | state: :speaking}}

      type == "response.audio_transcript.done" or type == "response.done" ->
        emit_event(session, :response_completed, event)
        {:noreply, %{session | state: :idle}}

      String.ends_with?(type, ".completed") ->
        emit_event(session, :response_completed, event)
        # Play any buffered audio output if present (macOS afplay)
        case session.audio_buffer do
          [] ->
            :ok

          [pcm] when is_binary(pcm) and byte_size(pcm) > 0 ->
            Task.start(fn -> LivekitexAgent.AudioSink.play_pcm16([pcm]) end)

          chunks when is_list(chunks) ->
            Task.start(fn -> LivekitexAgent.AudioSink.play_pcm16(chunks) end)
        end

        {:noreply, %{session | state: :idle, audio_buffer: []}}

      true ->
        emit_event(session, :response_event, event)
        {:noreply, session}
    end
  end

  defp handle_tool_calls(session, tool_calls) do
    # Update current turn with tool calls if present
    updated_turn = if session.current_turn do
      %{session.current_turn | tool_calls: tool_calls}
    else
      session.current_turn
    end

    # Update metrics
    updated_metrics = %{session.metrics |
      tool_calls_executed: session.metrics.tool_calls_executed + length(tool_calls)
    }

    session = %{session |
      current_turn: updated_turn,
      metrics: updated_metrics,
      last_activity_at: DateTime.utc_now()
    }

    # Execute each tool call
    Enum.each(tool_calls, fn tool_call ->
      execute_tool(session, tool_call)
    end)

    {:noreply, session}
  end

  defp execute_tool(session, %{name: tool_name, arguments: args}) do
    # Emit tool called event
    emit_event(session, :tool_called, %{
      tool_name: tool_name,
      arguments: args,
      timestamp: DateTime.utc_now()
    })

    # Create run context for the tool execution
    run_context =
      LivekitexAgent.RunContext.new(
        session: self(),
        function_call: %{name: tool_name, arguments: args},
        user_data: session.user_data
      )

    # Execute via FunctionTool registry to support explicit tool definitions
    Task.start(fn ->
      case LivekitexAgent.FunctionTool.execute_tool(tool_name, args, run_context) do
        {:ok, result} ->
          send(self(), {:tool_result, tool_name, result})

        {:error, reason} ->
          Logger.error("Tool execution error: #{inspect(reason)}")
          send(self(), {:tool_error, tool_name, reason})
      end
    end)
  end
end
