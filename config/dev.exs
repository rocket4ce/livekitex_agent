# Development environment configuration
import Config

# Development specific settings
config :livekitex_agent,
  # LiveKit connection for development
  livekit: [
    server_url: System.get_env("LIVEKIT_URL") || "ws://localhost:7880",
    api_key: System.get_env("LIVEKIT_API_KEY") || "devkey",
    api_secret: System.get_env("LIVEKIT_API_SECRET") || "secret"
  ],

  # OpenAI provider configuration
  openai: [
    api_key: System.get_env("OPENAI_API_KEY"),
    base_url: "https://api.openai.com/v1",
    llm_model: "gpt-4-turbo-preview",
    stt_model: "whisper-1",
    tts_model: "tts-1",
    tts_voice: "alloy"
  ],

  # Development worker options
  default_worker_options: [
    max_concurrent_jobs: 5,
    drain_timeout: 10_000,  # Shorter timeout for dev
    health_check_port: 8080,
    log_level: :debug
  ]

# More verbose logging in development
config :logger,
  level: :debug,
  compile_time_purge_matching: [
    [level_lower_than: :debug]
  ]
