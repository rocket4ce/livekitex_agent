# Production environment configuration
import Config

# Production specific settings
config :livekitex_agent,
  # LiveKit connection for production - must be set via environment variables
  livekit: [
    server_url: System.get_env("LIVEKIT_URL") || raise("LIVEKIT_URL environment variable is required"),
    api_key: System.get_env("LIVEKIT_API_KEY") || raise("LIVEKIT_API_KEY environment variable is required"),
    api_secret: System.get_env("LIVEKIT_API_SECRET") || raise("LIVEKIT_API_SECRET environment variable is required")
  ],

  # OpenAI provider configuration - must be set via environment variables
  openai: [
    api_key: System.get_env("OPENAI_API_KEY") || raise("OPENAI_API_KEY environment variable is required"),
    base_url: System.get_env("OPENAI_BASE_URL") || "https://api.openai.com/v1",
    llm_model: System.get_env("OPENAI_LLM_MODEL") || "gpt-4-turbo-preview",
    stt_model: System.get_env("OPENAI_STT_MODEL") || "whisper-1",
    tts_model: System.get_env("OPENAI_TTS_MODEL") || "tts-1",
    tts_voice: System.get_env("OPENAI_TTS_VOICE") || "alloy"
  ],

  # Production worker options
  default_worker_options: [
    max_concurrent_jobs: String.to_integer(System.get_env("MAX_CONCURRENT_JOBS") || "100"),
    drain_timeout: String.to_integer(System.get_env("DRAIN_TIMEOUT") || "60000"),
    health_check_port: String.to_integer(System.get_env("HEALTH_CHECK_PORT") || "8080"),
    log_level: :info
  ],

  # Production session settings
  session: [
    idle_timeout: String.to_integer(System.get_env("SESSION_IDLE_TIMEOUT") || "600000"),  # 10 minutes
    max_conversation_turns: String.to_integer(System.get_env("MAX_CONVERSATION_TURNS") || "1000")
  ]

# Production logging
config :logger,
  level: :info,
  backends: [:console],
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

# Enable SASL error logging in production
config :sasl, errlog_type: :error
