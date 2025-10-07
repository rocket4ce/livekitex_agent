# Main configuration for LivekitexAgent
import Config

# Phoenix Integration Configuration
#
# LivekitexAgent supports zero-configuration Phoenix integration.
# Simply add {:livekitex_agent, "~> 0.1.0"} to your deps and run `mix phx.server`
#
# For custom configuration, uncomment and modify the options below:

config :livekitex_agent,
  # Worker configuration - all options are optional with sensible defaults
  default_worker_options: [
    # Core worker settings
    # worker_pool_size: 4,                    # Number of worker processes (default: System.schedulers_online())
    # timeout: 300_000,                       # Job timeout in milliseconds (default: 5 minutes)
    # entry_point: &MyAgent.handle_job/1,     # Custom job handler (default: auto-generated)

    # LiveKit connection settings
    # server_url: "ws://localhost:7880",      # LiveKit server URL
    # api_key: "",                            # LiveKit API key
    # api_secret: "",                         # LiveKit API secret

    # Agent configuration
    # agent_name: "elixir_agent",             # Agent identifier
    # worker_type: :voice_agent,              # Agent type (:voice_agent, :multimodal_agent, etc.)

    # Advanced options (all have sensible defaults)
    max_concurrent_jobs: 10,                  # Maximum concurrent jobs per worker
    # drain_timeout: 30_000,                  # Graceful shutdown timeout
    health_check_port: 8080                   # Health check endpoint port
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
