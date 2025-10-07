#!/usr/bin/env elixir

# Real-time Joke Teller Agent Example
#
# This example demonstrates all Phase 6 real-time voice agent features:
# - Sub-100ms latency audio processing
# - Voice Activity Detection (VAD) with real-time interruption
# - Multi-modal stream management (audio, video, text)
# - Advanced WebRTC optimization
# - Real-time performance monitoring
# - Speech interruption handling
# - Adaptive quality control
#
# Usage:
#   elixir examples/realtime_joke_teller.exs
#
# Environment Variables:
#   LIVEKIT_URL - LiveKit server URL (default: ws://localhost:7880)
#   LIVEKIT_API_KEY - LiveKit API key
#   LIVEKIT_API_SECRET - LiveKit API secret
#   OPENAI_API_KEY - OpenAI API key for LLM
#   ROOM_NAME - Room name to join (default: joke-room-#{:rand.uniform(10000)})

Mix.install([
  {:livekitex_agent, path: "."},
  {:livekitex, "~> 0.1.34"},
  {:jason, "~> 1.4"},
  {:httpoison, "~> 2.0"},
  {:timex, "~> 3.7"}
])

defmodule RealtimeJokeTeller do
  @moduledoc """
  A real-time joke telling agent that showcases all Phase 6 features.

  This agent:
  - Tells jokes on demand with ultra-low latency
  - Responds to voice interruptions naturally
  - Supports multi-modal interactions (voice + text + video)
  - Monitors and optimizes its own performance in real-time
  - Adapts to network conditions automatically
  - Provides a rich conversational experience

  Key Features Demonstrated:
  - Real-time VAD with <20ms detection latency
  - Speech interruption with graceful recovery
  - Multi-modal context switching
  - Performance monitoring with alerts
  - Adaptive quality control
  - WebRTC optimization
  """

  use LivekitexAgent.Agent

  require Logger

  alias LivekitexAgent.{
    Agent,
    AgentSession,
    JobContext,
    RunContext,
    VADClient,
    SpeechHandle,
    StreamManager,
    InterruptionHandler,
    PerformanceOptimizer,
    AdvancedFeatures,
    RealtimeMonitor
  }

  # Agent configuration optimized for real-time performance
  @agent_config %{
    # Ultra-low latency configuration
    audio_processing: %{
      target_latency_ms: 30,
      buffer_size_ms: 20,
      sample_rate: 16000,
      channels: 1,
      format: :pcm
    },

    # VAD configuration for responsive interruptions
    vad_config: %{
      sensitivity: 0.7,
      min_speech_duration_ms: 100,
      min_silence_duration_ms: 200,
      speech_pad_ms: 50
    },

    # Performance targets
    performance_targets: %{
      audio_latency_ms: 30,
      end_to_end_latency_ms: 80,
      interruption_response_ms: 50,
      audio_quality_score: 4.5
    },

    # WebRTC optimization
    webrtc_config: %{
      adaptive_quality: true,
      bandwidth_optimization: true,
      connection_monitoring: true,
      quality_profiles: [:ultra_low_latency, :high_quality, :balanced]
    }
  }

  # Joke categories and content
  @joke_categories %{
    "programming" => [
      "Why do programmers prefer dark mode? Because light attracts bugs!",
      "How many programmers does it take to change a light bulb? None, that's a hardware problem!",
      "Why don't programmers like nature? It has too many bugs!",
      "What's a programmer's favorite hangout place? Foo Bar!",
      "Why do Java developers wear glasses? Because they can't C#!"
    ],
    "dad" => [
      "I'm reading a book about anti-gravity. It's impossible to put down!",
      "Why don't scientists trust atoms? Because they make up everything!",
      "Did you hear about the mathematician who's afraid of negative numbers? He'll stop at nothing to avoid them!",
      "Why don't eggs tell jokes? They'd crack each other up!",
      "What do you call a fake noodle? An impasta!"
    ],
    "ai" => [
      "Why did the neural network break up with the decision tree? It said their relationship was too linear!",
      "What's an AI's favorite type of music? Algo-rhythms!",
      "Why don't robots ever panic? They have great artificial composure!",
      "What did the deep learning model say to the data? You complete me... literally!",
      "Why was the chatbot so good at comedy? It had great training data!"
    ]
  }

  # State for tracking conversation context
  defstruct [
    :session_pid,
    :monitor_pid,
    :vad_client,
    :speech_handle,
    :stream_manager,
    :interruption_handler,
    :performance_optimizer,
    :advanced_features,
    current_category: "programming",
    joke_count: 0,
    interruption_count: 0,
    conversation_state: :idle,
    performance_grade: :excellent,
    user_preferences: %{},
    context_history: []
  ]

  @impl Agent
  def init(job_context) do
    Logger.info("🎭 Initializing RealtimeJokeTeller with ultra-low latency configuration")

    # Initialize real-time monitoring first
    {:ok, monitor_pid} = RealtimeMonitor.start_link(
      session_pid: job_context.session_pid,
      components: [:audio_processor, :webrtc_handler, :vad_client, :stream_manager, :session],
      performance_targets: @agent_config.performance_targets
    )

    # Subscribe to performance updates
    RealtimeMonitor.subscribe_to_updates(monitor_pid, self())

    # Initialize VAD with real-time configuration
    {:ok, vad_client} = VADClient.start_link(@agent_config.vad_config)

    # Initialize speech handling with interruption support
    {:ok, speech_handle} = SpeechHandle.start_link(
      session_pid: job_context.session_pid,
      vad_client: vad_client
    )

    # Initialize multi-modal stream manager
    {:ok, stream_manager} = StreamManager.start_link(
      session_pid: job_context.session_pid
    )

    # Initialize interruption handler
    {:ok, interruption_handler} = InterruptionHandler.start_link(
      vad_client: vad_client,
      speech_handle: speech_handle,
      strategy: :graceful_with_context
    )

    # Initialize performance optimizer
    {:ok, performance_optimizer} = PerformanceOptimizer.start_link(
      session_pid: job_context.session_pid,
      target_latency_ms: @agent_config.performance_targets.audio_latency_ms
    )

    # Initialize advanced WebRTC features
    {:ok, advanced_features} = AdvancedFeatures.start_link(
      session_pid: job_context.session_pid,
      config: @agent_config.webrtc_config
    )

    state = %__MODULE__{
      session_pid: job_context.session_pid,
      monitor_pid: monitor_pid,
      vad_client: vad_client,
      speech_handle: speech_handle,
      stream_manager: stream_manager,
      interruption_handler: interruption_handler,
      performance_optimizer: performance_optimizer,
      advanced_features: advanced_features
    }

    # Enable multi-modal support
    AgentSession.enable_video_stream(job_context.session_pid, %{
      resolution: {640, 480},
      fps: 15,
      codec: :h264
    })

    # Send welcome message with performance info
    welcome_message = """
    🎭 Welcome to the Real-time Joke Teller!

    I'm optimized for ultra-low latency with sub-100ms response times.
    I support:
    • 🎤 Voice interactions with real-time interruption
    • 📹 Video streaming and visual cues
    • 💬 Text chat alongside voice
    • 📊 Real-time performance monitoring
    • 🔧 Adaptive quality optimization

    Try saying:
    • "Tell me a programming joke"
    • "Switch to dad jokes"
    • "How's your performance?"
    • Or just interrupt me anytime!

    Ready to make you laugh! 😄
    """

    SpeechHandle.start_speech(speech_handle, welcome_message, %{
      priority: :high,
      interruptible: true
    })

    Logger.info("🚀 RealtimeJokeTeller initialized with all real-time features enabled")
    {:ok, state}
  end

  @impl Agent
  def handle_user_speech(text, state) do
    Logger.info("👤 User said: #{text}")

    # Update conversation context
    new_context = [%{type: :user_speech, content: text, timestamp: System.monotonic_time(:millisecond)} | state.context_history]
    state = %{state | context_history: Enum.take(new_context, 10)} # Keep last 10 interactions

    # Process the speech input
    response = process_user_input(text, state)

    # Generate appropriate response
    handle_response(response, state)
  end

  @impl Agent
  def handle_user_text(text, state) do
    Logger.info("💬 User texted: #{text}")

    # Handle text input similarly to speech but with text-specific formatting
    response = process_user_input(text, state)

    # Send both text and speech response for multi-modal experience
    AgentSession.send_text_response(state.session_pid, response.text)

    if response.speak do
      SpeechHandle.start_speech(state.speech_handle, response.speak, %{
        priority: :normal,
        interruptible: true
      })
    end

    {:ok, update_state_with_response(state, response)}
  end

  @impl Agent
  def handle_interruption(context, state) do
    Logger.info("🛑 Speech interrupted: #{inspect(context)}")

    # Increment interruption counter
    state = %{state | interruption_count: state.interruption_count + 1}

    # Handle the interruption gracefully
    response = case context do
      %{partial_text: partial} when byte_size(partial) > 0 ->
        "Oh! You interrupted me while I was saying '#{partial}'. What would you like instead?"

      _ ->
        "Sorry, I got interrupted! What can I help you with?"
    end

    # Quick response to interruption
    SpeechHandle.start_speech(state.speech_handle, response, %{
      priority: :urgent,
      interruptible: true
    })

    {:ok, %{state | conversation_state: :interrupted}}
  end

  @impl Agent
  def handle_video_frame(frame_data, state) do
    # Process video frame for visual cues (placeholder implementation)
    StreamManager.add_stream(state.stream_manager, :video, frame_data, %{
      timestamp: System.monotonic_time(:millisecond),
      format: :h264
    })

    # Could add visual joke analysis here
    {:ok, state}
  end

  @impl Agent
  def handle_info({:performance_update, metrics}, state) do
    # Handle real-time performance updates
    health_score = get_in(metrics, [:derived, :system_health_score]) || 100
    performance_grade = get_in(metrics, [:derived, :performance_grade]) || :excellent

    state = %{state | performance_grade: performance_grade}

    # React to performance changes
    case performance_grade do
      grade when grade in [:poor, :critical] ->
        Logger.warning("⚠️ Performance degraded to #{grade}, optimizing...")
        PerformanceOptimizer.optimize(state.performance_optimizer)

      :fair ->
        Logger.info("📊 Performance is fair, monitoring closely...")

      _ ->
        # Performance is good, continue normally
        :ok
    end

    {:noreply, state}
  end

  @impl Agent
  def handle_info({:vad_event, event}, state) do
    # Handle Voice Activity Detection events
    case event do
      {:speech_started, confidence} ->
        Logger.debug("🎤 Speech detected (confidence: #{confidence})")
        InterruptionHandler.handle_speech_start(state.interruption_handler)

      {:speech_ended, duration} ->
        Logger.debug("🔇 Speech ended (duration: #{duration}ms)")
        InterruptionHandler.handle_speech_end(state.interruption_handler)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  # Private helper functions

  defp process_user_input(text, state) do
    text_lower = String.downcase(text)

    cond do
      contains_any?(text_lower, ["joke", "funny", "laugh", "humor"]) ->
        handle_joke_request(text_lower, state)

      contains_any?(text_lower, ["programming", "code", "developer", "tech"]) ->
        change_category("programming", state)

      contains_any?(text_lower, ["dad joke", "dad", "family"]) ->
        change_category("dad", state)

      contains_any?(text_lower, ["ai", "artificial intelligence", "robot", "machine"]) ->
        change_category("ai", state)

      contains_any?(text_lower, ["performance", "latency", "speed", "quality"]) ->
        handle_performance_query(state)

      contains_any?(text_lower, ["stop", "quiet", "pause"]) ->
        handle_stop_request(state)

      contains_any?(text_lower, ["hello", "hi", "hey"]) ->
        handle_greeting(state)

      contains_any?(text_lower, ["help", "what can you do"]) ->
        handle_help_request(state)

      true ->
        handle_general_conversation(text, state)
    end
  end

  defp handle_joke_request(text, state) do
    # Select joke based on current category
    jokes = Map.get(@joke_categories, state.current_category, @joke_categories["programming"])
    joke = Enum.random(jokes)

    # Performance-optimized response
    response_text = "Here's a #{state.current_category} joke for you: #{joke}"

    # Add some personality based on performance
    personality_addition = case state.performance_grade do
      :excellent -> " I'm running at peak performance, so this one should be extra crisp! 😄"
      :good -> " Running smoothly and ready to deliver! 😊"
      :fair -> " Still delivering quality humor despite some performance challenges! 🙂"
      _ -> " Even with some technical hiccups, the jokes must go on! 😅"
    end

    %{
      text: response_text <> personality_addition,
      speak: response_text,
      category: :joke,
      new_state: %{state | joke_count: state.joke_count + 1, conversation_state: :telling_joke}
    }
  end

  defp change_category(new_category, state) do
    %{
      text: "Switching to #{new_category} jokes! Let me tell you one:",
      speak: "Switching to #{new_category} jokes!",
      category: :category_change,
      new_state: %{state | current_category: new_category, conversation_state: :category_changed}
    }
  end

  defp handle_performance_query(state) do
    # Get current performance metrics
    metrics = RealtimeMonitor.get_performance_snapshot(state.monitor_pid)
    health_score = get_in(metrics, [:derived, :system_health_score]) || 100
    latency = get_in(metrics, [:derived, :end_to_end_latency_ms]) || 0

    performance_report = """
    📊 My current performance stats:
    • Health Score: #{Float.round(health_score, 1)}/100
    • Response Latency: #{Float.round(latency, 1)}ms
    • Performance Grade: #{state.performance_grade}
    • Jokes Told: #{state.joke_count}
    • Interruptions Handled: #{state.interruption_count}

    I'm optimized for sub-100ms responses and real-time interaction!
    """

    %{
      text: performance_report,
      speak: "My health score is #{Float.round(health_score, 1)} out of 100, with #{Float.round(latency, 1)} millisecond latency. Performance grade: #{state.performance_grade}.",
      category: :performance,
      new_state: %{state | conversation_state: :performance_report}
    }
  end

  defp handle_stop_request(state) do
    # Immediately stop current speech
    SpeechHandle.interrupt(state.speech_handle)

    %{
      text: "🛑 Stopped! What would you like to do next?",
      speak: "Stopped! What would you like to do next?",
      category: :control,
      new_state: %{state | conversation_state: :stopped}
    }
  end

  defp handle_greeting(state) do
    greetings = [
      "Hello! Ready for some real-time laughs?",
      "Hi there! I'm your ultra-low-latency joke companion!",
      "Hey! Want to hear a joke with sub-100ms delivery?",
      "Greetings! I'm optimized for maximum humor with minimum delay!"
    ]

    greeting = Enum.random(greetings)

    %{
      text: greeting,
      speak: greeting,
      category: :greeting,
      new_state: %{state | conversation_state: :greeted}
    }
  end

  defp handle_help_request(state) do
    help_text = """
    🤖 I'm a real-time joke telling agent! Here's what I can do:

    **Joke Commands:**
    • "Tell me a joke" - Random joke from current category
    • "Programming joke" - Switch to programming humor
    • "Dad joke" - Switch to dad jokes
    • "AI joke" - Switch to AI/tech humor

    **Performance Commands:**
    • "How's your performance?" - Get real-time stats
    • "Stop" - Interrupt current speech immediately

    **Real-time Features:**
    • 🎤 Ultra-low latency voice responses (<100ms)
    • 🛑 Instant interruption handling
    • 📊 Live performance monitoring
    • 🔧 Adaptive quality optimization
    • 💬 Multi-modal interaction (voice + text + video)

    Just start talking - I'll respond in real-time! 🚀
    """

    %{
      text: help_text,
      speak: "I can tell jokes in real-time with ultra-low latency, handle interruptions gracefully, and adapt to performance conditions. Just ask for a joke or try interrupting me!",
      category: :help,
      new_state: %{state | conversation_state: :help_provided}
    }
  end

  defp handle_general_conversation(text, state) do
    # Handle general conversation with personality
    responses = [
      "That's interesting! Would you like to hear a #{state.current_category} joke about it?",
      "I see! I'm optimized for jokes, but I can chat too. Want a quick joke?",
      "Hmm, that's outside my comedy specialty, but here's what I can do - tell amazing #{state.current_category} jokes!",
      "Thanks for sharing! My real-time joke engine is ready when you are!"
    ]

    response = Enum.random(responses)

    %{
      text: response,
      speak: response,
      category: :general,
      new_state: %{state | conversation_state: :general_chat}
    }
  end

  defp handle_response(response, state) do
    # Send the appropriate response
    SpeechHandle.start_speech(state.speech_handle, response.speak, %{
      priority: :normal,
      interruptible: true
    })

    # Update state
    new_state = Map.get(response, :new_state, state)
    {:ok, new_state}
  end

  defp update_state_with_response(state, response) do
    Map.get(response, :new_state, state)
  end

  defp contains_any?(text, keywords) do
    Enum.any?(keywords, &String.contains?(text, &1))
  end

  # Run the agent
  def run do
    # Configuration
    config = %{
      livekit_url: System.get_env("LIVEKIT_URL", "ws://localhost:7880"),
      livekit_api_key: System.get_env("LIVEKIT_API_KEY"),
      livekit_api_secret: System.get_env("LIVEKIT_API_SECRET"),
      room_name: System.get_env("ROOM_NAME", "joke-room-#{:rand.uniform(10000)}"),
      agent_name: "RealtimeJokeTeller",
      # Ultra-low latency configuration
      audio_config: @agent_config.audio_processing
    }

    Logger.info("🎭 Starting RealtimeJokeTeller Agent")
    Logger.info("📡 Connecting to: #{config.livekit_url}")
    Logger.info("🏠 Room: #{config.room_name}")
    Logger.info("⚡ Target latency: #{@agent_config.performance_targets.audio_latency_ms}ms")

    # Validate configuration
    unless config.livekit_api_key && config.livekit_api_secret do
      Logger.error("❌ Missing required environment variables: LIVEKIT_API_KEY and LIVEKIT_API_SECRET")
      System.halt(1)
    end

    # Start the agent
    case Agent.start_link(__MODULE__, config) do
      {:ok, agent_pid} ->
        Logger.info("✅ RealtimeJokeTeller started successfully!")
        Logger.info("🎤 Ready for real-time voice interactions with sub-100ms latency")
        Logger.info("🛑 Try interrupting me while I'm speaking!")
        Logger.info("📊 Performance monitoring active")

        # Keep the agent running
        Process.monitor(agent_pid)
        receive do
          {:DOWN, _ref, :process, ^agent_pid, reason} ->
            Logger.error("❌ Agent stopped: #{inspect(reason)}")
            System.halt(1)
        end

      {:error, reason} ->
        Logger.error("❌ Failed to start agent: #{inspect(reason)}")
        System.halt(1)
    end
  end
end

# Start the agent if this file is run directly
if __ENV__.file == :code.get_object_code(RealtimeJokeTeller)[:source] do
  RealtimeJokeTeller.run()
end
