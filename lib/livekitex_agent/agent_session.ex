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
    :audio_buffer
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
          audio_buffer: list()
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
  Stops the agent session.
  """
  def stop(session_pid) do
    GenServer.stop(session_pid)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    agent = Keyword.fetch!(opts, :agent)

    session = %__MODULE__{
      agent: agent,
      session_id: generate_session_id(),
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
      user_data: %{},
      started_at: DateTime.utc_now(),
      audio_buffer: []
    }

    Logger.info("Agent session started: #{session.session_id}")
    emit_event(session, :session_started, %{session_id: session.session_id})

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

    # Update state to listening if idle
    session = if session.state == :idle, do: %{session | state: :listening}, else: session

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

    session = %{session | state: :processing}
    emit_event(session, :text_received, %{text: text})

    # Add user message to chat context
    updated_context = session.chat_context ++ [%{role: "user", content: text}]
    session = %{session | chat_context: updated_context}

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

    session = %{session | state: :interrupted, current_turn: nil}
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
  def handle_info({:tts_complete, audio_data}, session) do
    Logger.info("TTS synthesis complete")
    emit_event(session, :tts_complete, %{audio_size: byte_size(audio_data)})

    session = %{session | state: :idle}
    {:noreply, session}
  end

  @impl true
  def handle_info({:tool_result, tool_name, result}, session) do
    Logger.info("Tool #{tool_name} completed with result")

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

  # Private functions

  defp generate_session_id do
    :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
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

  defp emit_event(session, event_type, data) do
    case Map.get(session.event_callbacks, event_type) do
      nil ->
        :ok

      callback_fun when is_function(callback_fun) ->
        try do
          callback_fun.(event_type, data)
        rescue
          error ->
            Logger.error("Error in event callback for #{event_type}: #{inspect(error)}")
        end
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
    session = %{session | chat_context: updated_context, state: :speaking}

    # Send to TTS if available
    case session.tts_client do
      nil ->
        Logger.warning("No TTS client available")
        {:noreply, %{session | state: :idle}}

      tts_pid ->
        send(tts_pid, {:synthesize, response})
        emit_event(session, :speaking_started, %{text: response})
        {:noreply, session}
    end
  end

  defp handle_realtime_response_event(%{"type" => type} = event, session) do
    cond do
      String.ends_with?(type, ".delta") ->
        # Streamed delta: could contain text or audio
        emit_event(session, :response_delta, event)
        {:noreply, %{session | state: :speaking}}

      String.ends_with?(type, ".completed") ->
        emit_event(session, :response_completed, event)
        # Play any buffered audio if present (macOS afplay)
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
    # Execute each tool call
    Enum.each(tool_calls, fn tool_call ->
      execute_tool(session, tool_call)
    end)

    {:noreply, session}
  end

  defp execute_tool(session, %{name: tool_name, arguments: args}) do
    case Map.get(session.tool_registry, String.to_atom(tool_name)) do
      nil ->
        Logger.warning("Tool not found: #{tool_name}")

      tool_config ->
        # Create run context
        run_context =
          LivekitexAgent.RunContext.new(
            session: self(),
            function_call: %{name: tool_name, arguments: args},
            user_data: session.user_data
          )

        # Execute tool in separate process
        Task.start(fn ->
          try do
            result = apply(tool_config.module, :execute, [args, run_context])
            send(self(), {:tool_result, tool_name, result})
          rescue
            error ->
              Logger.error("Tool execution error: #{inspect(error)}")
              send(self(), {:tool_result, tool_name, "Error: #{inspect(error)}"})
          end
        end)
    end
  end
end
