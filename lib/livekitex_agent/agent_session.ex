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
    :started_at
  ]

  @type session_state :: :idle | :listening | :processing | :speaking | :interrupted | :stopped

  @type t :: %__MODULE__{
          agent: LivekitexAgent.Agent.t(),
          session_id: String.t(),
          llm_client: pid() | nil,
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
          started_at: DateTime.t()
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
      started_at: DateTime.utc_now()
    }

    Logger.info("Agent session started: #{session.session_id}")
    emit_event(session, :session_started, %{session_id: session.session_id})

    {:ok, session}
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
