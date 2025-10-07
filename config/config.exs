# Main configuration for LivekitexAgent
import Config

# Base configuration that applies to all environments
config :livekitex_agent,
  # Default worker options
  default_worker_options: [
    max_concurrent_jobs: 10,
    drain_timeout: 30_000,
    health_check_port: 8080
  ],

  # Tool registry options
  tool_registry: [
    auto_discover: true,
    timeout: 60_000
  ],

  # Media processing defaults
  media: [
    audio_format: :pcm16,
    sample_rate: 48_000,
    channels: 1,
    vad_sensitivity: 0.5
  ],

  # Session defaults
  session: [
    idle_timeout: 300_000,
    max_conversation_turns: 100
  ]

# Logger configuration
config :logger,
  level: :info,
  backends: [:console],
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

# Import environment specific config
import_config "#{config_env()}.exs"
