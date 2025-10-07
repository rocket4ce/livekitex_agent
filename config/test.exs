# Test environment configuration
import Config

# Test specific settings
config :livekitex_agent,
  # Mock LiveKit connection for testing
  livekit: [
    server_url: "ws://localhost:7880",
    api_key: "test-key",
    api_secret: "test-secret"
  ],

  # Mock OpenAI provider configuration
  openai: [
    api_key: "test-openai-key",
    base_url: "https://api.openai.com/v1",
    llm_model: "gpt-3.5-turbo",
    stt_model: "whisper-1",
    tts_model: "tts-1",
    tts_voice: "alloy"
  ],

  # Test worker options
  default_worker_options: [
    max_concurrent_jobs: 2,
    # Very short timeout for tests
    drain_timeout: 5_000,
    # Different port to avoid conflicts
    health_check_port: 8081,
    log_level: :warning
  ],

  # Faster timeouts for testing
  session: [
    # 30 seconds
    idle_timeout: 30_000,
    max_conversation_turns: 10
  ]

# Reduced logging in tests
config :logger,
  level: :warning,
  # No output during tests unless there's an error
  backends: [],
  compile_time_purge_matching: [
    [level_lower_than: :warn]
  ]
